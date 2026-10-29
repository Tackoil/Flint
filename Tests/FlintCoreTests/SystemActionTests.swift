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
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: true, isEjectable: true, isRemovable: true))
        #expect(SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: true, isRemovable: false))
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: false, isRemovable: false))
        #expect(SystemActionExecutor.isEjectableVolume(isInternal: false, isEjectable: false, isRemovable: true))
        #expect(!SystemActionExecutor.isEjectableVolume(isInternal: nil, isEjectable: nil, isRemovable: nil))
    }

    @Test func actionErrorsPropagateToTheCaller() async {
        let executor = SystemActionExecutor(emptyTrash: { throw TestError() }, showDesktop: { throw TestError() })
        await #expect(throws: TestError.self) { try await executor.perform(.emptyTrash) }
        await #expect(throws: TestError.self) { try await executor.perform(.showDesktop) }
    }
}
