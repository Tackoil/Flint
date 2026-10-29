import Foundation
import Testing
import UserNotifications
@testable import FlintCore

@MainActor
struct LauncherErrorNotifierTests {
    private struct TestError: LocalizedError {
        var errorDescription: String? { "The disk is busy. Try again after closing its files." }
    }

    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional])
    func authorizedFailuresIncludeActionAndError(status: UNAuthorizationStatus) async throws {
        var requests: [UNNotificationRequest] = []
        let notifier = LauncherErrorNotifier(authorizationStatus: { status }, requestAuthorization: {
            Issue.record("Existing permission should not prompt again")
            return false
        }, addNotification: { requests.append($0) })
        await notifier.notifyFailure(for: .ejectAllDisks, error: TestError())
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.content.title == "Couldn’t run Eject All Disks")
        #expect(request.content.body == TestError().localizedDescription)
        #expect(request.content.sound != nil)
        #expect(request.trigger == nil)
    }

    @Test(arguments: [true, false])
    func firstFailureRequestsPermissionBeforeDelivery(granted: Bool) async {
        var events: [String] = []
        let notifier = LauncherErrorNotifier(authorizationStatus: { .notDetermined }, requestAuthorization: {
            events.append("permission")
            return granted
        }, addNotification: { _ in events.append("notification") })
        await notifier.notifyFailure(for: .emptyTrash, error: TestError())
        #expect(events == (granted ? ["permission", "notification"] : ["permission"]))
    }

    @Test func deniedPermissionDoesNotPromptOrDeliver() async {
        let notifier = LauncherErrorNotifier(authorizationStatus: { .denied }, requestAuthorization: {
            Issue.record("A denied permission must not prompt again")
            return true
        }, addNotification: { _ in Issue.record("Notifications are disabled") })
        await notifier.notifyFailure(for: .showDesktop, error: TestError())
    }

    @Test func repeatedFailuresHaveSeparateNotifications() async {
        var identifiers: [String] = []
        let notifier = LauncherErrorNotifier(authorizationStatus: { .authorized }, addNotification: {
            identifiers.append($0.identifier)
        })
        await notifier.notifyFailure(for: .showDesktop, error: TestError())
        await notifier.notifyFailure(for: .showDesktop, error: TestError())
        #expect(Set(identifiers).count == 2)
    }

    @Test func permissionRequestFailureDoesNotAttemptDelivery() async {
        let notifier = LauncherErrorNotifier(authorizationStatus: { .notDetermined }, requestAuthorization: {
            throw TestError()
        }, addNotification: { _ in Issue.record("Authorization did not succeed") })
        await notifier.notifyFailure(for: .emptyTrash, error: TestError())
    }

    @Test func applicationLaunchFailureIncludesApplicationAndError() async throws {
        let app = ApplicationRecord(name: "Missing App", bundleIdentifier: nil,
                                    url: URL(fileURLWithPath: "/Applications/Missing App.app"))
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                            userInfo: [NSLocalizedDescriptionKey: "The application no longer exists."])
        var requests: [UNNotificationRequest] = []
        let notifier = LauncherErrorNotifier(authorizationStatus: { .authorized }, addNotification: {
            requests.append($0)
        })
        await notifier.notifyLaunchFailure(for: app, error: error)
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.content.title == "Couldn’t open Missing App")
        #expect(request.content.body == error.localizedDescription)
        #expect(request.content.sound != nil)
        #expect(request.trigger == nil)
    }
}
