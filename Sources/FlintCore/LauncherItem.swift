import Foundation

enum LauncherItem: Hashable, Identifiable, Sendable {
    case application(ApplicationRecord)
    case action(SystemAction)
    case translation
    case qrCode

    var id: String {
        switch self {
        case .application(let application): return "application:\(application.id)"
        case .action(let action): return "action:\(action.id)"
        case .qrCode: return "qrCode"
        case .translation: return "translation"
        }
    }

    var name: String {
        switch self {
        case .application(let application): return application.name
        case .action(let action): return action.name
        case .qrCode: return "QR Code Generator"
        case .translation: return "Translate"
        }
    }

    var kind: String {
        switch self {
        case .application: return "Application"
        case .action: return "Action"
        case .qrCode: return "Tool"
        case .translation: return "Action"
        }
    }

    var buttonTitle: String {
        switch self {
        case .application: return "Open Application"
        case .action: return "Run Action"
        case .qrCode: return "Generate QR Code"
        case .translation: return "Enter Translation"
        }
    }
}
