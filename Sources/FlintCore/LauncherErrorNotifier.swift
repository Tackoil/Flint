import OSLog
import UserNotifications

@MainActor
struct LauncherErrorNotifier {
    var authorizationStatus: @MainActor () async -> UNAuthorizationStatus = {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    var requestAuthorization: @MainActor () async throws -> Bool = {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    var addNotification: @MainActor (UNNotificationRequest) async throws -> Void = {
        try await UNUserNotificationCenter.current().add($0)
    }
    private static let logger = Logger(subsystem: "dev.saming.flint", category: "LauncherErrors")

    func notifyFailure(for action: SystemAction, error: Error) async {
        await notify(title: "Couldn’t run \(action.name)", error: error)
    }

    func notifyLaunchFailure(for app: ApplicationRecord, error: Error) async {
        await notify(title: "Couldn’t open \(app.name)", error: error)
    }

    private func notify(title: String, error: Error) async {
        Self.logger.error("\(title, privacy: .private): \(error.localizedDescription, privacy: .private)")
        do {
            guard try await canNotify() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = error.localizedDescription
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try await addNotification(request)
        } catch {
            Self.logger.error("Couldn’t deliver error notification: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func canNotify() async throws -> Bool {
        let status = await authorizationStatus()
        if status == .notDetermined {
            return try await requestAuthorization()
        }
        return status == .authorized || status == .provisional
    }
}
