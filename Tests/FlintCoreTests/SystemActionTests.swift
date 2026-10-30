import Foundation
import Testing
@testable import FlintCore

struct SystemActionTests {
    @Test(arguments: ["eject", "eject all disk", "EJECT ALL DISKS", "ead"])
    func findsEjectAction(query: String) {
        let items = SystemAction.allCases.map(LauncherItem.action)
        #expect(ApplicationSearch.filter(items, query: query) == [.action(.ejectAllDisks)])
    }

    @Test func actionsAndApplicationsShareSearchRanking() {
        let app = ApplicationRecord(name: "Show Desktop Helper", bundleIdentifier: nil,
                                    url: URL(fileURLWithPath: "/Applications/Show Desktop Helper.app"))
        let items = [LauncherItem.application(app)] + SystemAction.allCases.map(LauncherItem.action)
        #expect(ApplicationSearch.filter(items, query: " show desktop ") == [
            .action(.showDesktop), .application(app)
        ])
        #expect(ApplicationSearch.filter(items, query: "empty trash") == [.action(.emptyTrash)])
        #expect(ApplicationSearch.filter(items, query: "zzz").isEmpty)
    }

    @Test func onlyEmptyTrashNeedsConfirmation() {
        #expect(SystemAction.allCases.filter(\.requiresConfirmation) == [.emptyTrash])
    }
}

@MainActor
struct SystemActionExecutorTests {
    private struct TestError: LocalizedError {
        var errorDescription: String? { "Disk is busy" }
    }

    @Test func dispatchesToTheSelectedActionOnly() async throws {
        var calls: [String] = []
        let executor = SystemActionExecutor(
            listVolumes: { calls.append("list"); return [] },
            ejectVolume: { _ in calls.append("eject") },
            emptyTrash: { calls.append("trash") },
            showDesktop: { calls.append("desktop") }
        )
        try await executor.perform(.showDesktop)
        #expect(calls == ["desktop"])
        try await executor.perform(.emptyTrash)
        #expect(calls == ["desktop", "trash"])
        try await executor.perform(.ejectAllDisks)
        #expect(calls == ["desktop", "trash", "list"])
    }

    @Test func ejectAttemptsEveryDiskAndReportsFailures() async throws {
        let busy = URL(fileURLWithPath: "/Volumes/Busy Disk")
        let available = URL(fileURLWithPath: "/Volumes/Available Disk")
        var attempted: [URL] = []
        let executor = SystemActionExecutor(listVolumes: { [busy, available] }, ejectVolume: { volume in
            attempted.append(volume)
            if volume == busy { throw TestError() }
        })
        do {
            try await executor.perform(.ejectAllDisks)
            Issue.record("Expected the busy disk to produce an error")
        } catch {
            #expect(error.localizedDescription.contains("Busy Disk"))
            #expect(error.localizedDescription.contains("Disk is busy"))
        }
        #expect(attempted == [busy, available])
    }

    @Test func noEjectableDisksSucceedsWithoutEjectingAnything() async throws {
        let executor = SystemActionExecutor(listVolumes: { [] }, ejectVolume: { _ in
            Issue.record("There are no disks to eject")
        })
        try await executor.perform(.ejectAllDisks)
    }

    @Test func internalAndNonremovableVolumesAreExcluded() {
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: true, isEjectable: true,
                                                       isRemovable: true, isBrowsable: true))
        #expect(SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: true,
                                                      isRemovable: false, isBrowsable: true))
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: false,
                                                       isRemovable: false, isBrowsable: true))
        #expect(SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: false,
                                                      isRemovable: true, isBrowsable: true))
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: nil, isEjectable: nil,
                                                       isRemovable: nil, isBrowsable: true))
    }

    @Test(arguments: [false, nil] as [Bool?])
    func volumesMustBeBrowsableToEject(isBrowsable: Bool?) {
        // CoreSimulator reports an unknown internal status and both ejectable/removable flags.
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: nil, isEjectable: true,
                                                       isRemovable: true, isBrowsable: isBrowsable))
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: true,
                                                       isRemovable: true, isBrowsable: isBrowsable))
    }

    @Test func browsableDiskImagesWithUnknownInternalStatusRemainEjectable() {
        #expect(SystemActionExecutor.isEjectableVolume(isInternal: nil, isEjectable: true,
                                                      isRemovable: true, isBrowsable: true))
    }

    @Test func actionErrorsPropagateToTheCaller() async {
        let executor = SystemActionExecutor(emptyTrash: { throw TestError() }, showDesktop: { throw TestError() })
        await #expect(throws: TestError.self) { try await executor.perform(.emptyTrash) }
        await #expect(throws: TestError.self) { try await executor.perform(.showDesktop) }
    }

    @Test func finderPermissionFailureExplainsHowToAllowAutomation() async {
        do {
            try await SystemActionExecutor.emptyFinderTrash { _ in
                throw NSError(domain: "TestScript", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Not authorized to send Apple events to Finder. (-1743)"
                ])
            }
            Issue.record("Expected an Automation permission error")
        } catch {
            #expect(error.localizedDescription.contains("Privacy & Security → Automation"))
        }
    }

    @Test(arguments: [
        "42:53: execution error: Finder got an error: The operation can’t be completed. (-128)",
        "Finder couldn’t delete an item. (-43)",
        "An unrelated error. (-1280)",
        "Couldn’t delete (-128). (-43)",
        "Couldn’t delete -1743.txt. (-43)"
    ])
    func otherFinderFailuresRemainVisible(message: String) async {
        let failure = NSError(domain: "TestScript", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        do {
            try await SystemActionExecutor.emptyFinderTrash { _ in throw failure }
            Issue.record("Expected the Finder failure to propagate")
        } catch {
            #expect(error as NSError == failure)
        }
    }

    @Test(arguments: [true, false])
    func confirmedTrashScriptDeletesItemsAndRestoresWarning(originalWarning: Bool) async throws {
        try await SystemActionExecutor.runAppleScript(mockFinderScript(originalWarning: originalWarning, fails: false))
    }

    @Test(arguments: [true, false])
    func confirmedTrashScriptRestoresWarningAndPropagatesDeletionFailure(originalWarning: Bool) async throws {
        try await SystemActionExecutor.runAppleScript(mockFinderScript(originalWarning: originalWarning, fails: true))
    }

    @Test func confirmedTrashScriptRejectsSuccessWhenItemsRemain() async throws {
        try await SystemActionExecutor.runAppleScript(
            mockFinderScript(originalWarning: true, fails: false, retainsItems: true)
        )
    }

    @Test(arguments: [true, false])
    func alreadyEmptyTrashSucceedsWithoutRequestingDeletion(originalWarning: Bool) async throws {
        try await SystemActionExecutor.runAppleScript(
            mockFinderScript(originalWarning: originalWarning, fails: false, startsEmpty: true)
        )
    }

    private func mockFinderScript(originalWarning: Bool, fails: Bool,
                                  retainsItems: Bool = false, startsEmpty: Bool = false) -> String {
        let operation = SystemActionExecutor.confirmedEmptyTrashScript.replacingOccurrences(
            of: "tell application id \"com.apple.finder\"", with: "tell fakeFinder"
        ).replacingOccurrences(of: "items of trash", with: "remainingItems of trash")
            .replacingOccurrences(of: "delay 0.1", with: "delay 0")
        let expectedFailure = fails ? -43 : -2700
        // Execute the production AppleScript against a script object. No real
        // Finder events or user files are involved in these integration checks.
        return """
        using terms from application "/System/Library/CoreServices/Finder.app"
            script fakeTrash
                property warns before emptying : \(originalWarning)
                property remainingItems : \(startsEmpty ? "{}" : "{\"disposable test item\"}")
                property deletionAttempted : false
                on empty targetTrash
                    set deletionAttempted of me to true
                    if (count of remainingItems of me) is 0 then error "Already empty" number -128
                    if warns before emptying of me then error "Warning was not suppressed" number -128
                    if \(fails) then error "Deletion failed" number -43
                    if not \(retainsItems) then set remainingItems of me to {}
                end empty
            end script
            script fakeFinder
                property trash : fakeTrash
            end script
            on performOperation()
                \(operation)
            end performOperation
            set reportedFailure to false
            try
                performOperation()
            on error failureMessage number failureNumber
                if failureNumber is not \(expectedFailure) then error failureMessage number failureNumber
                set reportedFailure to true
            end try
            if (warns before emptying of fakeTrash) is not \(originalWarning) then error "Warning was not restored"
            if (deletionAttempted of fakeTrash) is not \(!startsEmpty) then error "Unexpected deletion request"
            if reportedFailure is not \(fails || retainsItems) then error "Deletion failure was not propagated"
            if not \(fails || retainsItems) and (count of remainingItems of fakeTrash) is not 0 then error "Items were not deleted"
        end using terms from
        """
    }
}
