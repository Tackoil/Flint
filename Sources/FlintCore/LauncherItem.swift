import Foundation

enum LauncherItem: Hashable, Identifiable, Sendable {
    case application(ApplicationRecord)
    case action(SystemAction)
    case translation

    var id: String {
        switch self {
        case .application(let application): return "application:\(application.id)"
        case .action(let action): return "action:\(action.id)"
        case .translation: return "translation"
        }
    }

    var name: String {
        switch self {
        case .application(let application): return application.name
        case .action(let action): return action.name
        case .translation: return "Translate"
        }
    }

    var kind: String {
        switch self {
        case .application: return "Application"
        case .action: return "Action"
        case .translation: return "Action"
        }
    }

    var buttonTitle: String {
        switch self {
        case .application: return "Open Application"
        case .action: return "Run Action"
        case .translation: return "Enter Translation"
        }
    }
}
