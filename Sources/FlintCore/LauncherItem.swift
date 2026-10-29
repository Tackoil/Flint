import Foundation

enum LauncherItem: Hashable, Identifiable, Sendable {
    case application(ApplicationRecord)
    case action(SystemAction)

    var id: String {
        switch self {
        case .application(let application): return "application:\(application.id)"
        case .action(let action): return "action:\(action.id)"
        }
    }

    var name: String {
        switch self {
        case .application(let application): return application.name
        case .action(let action): return action.name
        }
    }

    var kind: String {
        switch self {
        case .application: return "Application"
        case .action: return "Action"
        }
    }

    var buttonTitle: String {
        switch self {
        case .application: return "Open Application"
        case .action: return "Run Action"
        }
    }
}
