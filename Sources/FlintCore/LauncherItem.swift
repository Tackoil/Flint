import Foundation

enum LauncherItem: Hashable, Identifiable, Sendable {
    case application(ApplicationRecord)
    case action(SystemAction)
    case quickLink(QuickLink)
    case createQuickLink
    case translation
    case qrCode

    var id: String {
        switch self {
        case .application(let application): return "application:\(application.id)"
        case .action(let action): return "action:\(action.id)"
        case .quickLink(let link): return "quickLink:\(link.id)"
        case .createQuickLink: return "createQuickLink"
        case .qrCode: return "qrCode"
        case .translation: return "translation"
        }
    }

    var name: String {
        switch self {
        case .application(let application): return application.name
        case .action(let action): return action.name
        case .quickLink(let link): return link.name
        case .createQuickLink: return "Create Quick Link"
        case .qrCode: return "QR Code Generator"
        case .translation: return "Translate"
        }
    }

    var kind: String {
        switch self {
        case .application: return "Application"
        case .action: return "Action"
        case .quickLink: return "Quick Link"
        case .createQuickLink: return "Action"
        case .qrCode: return "Tool"
        case .translation: return "Action"
        }
    }

    var buttonTitle: String {
        switch self {
        case .application: return "Open Application"
        case .action: return "Run Action"
        case .quickLink: return "Open Quick Link"
        case .createQuickLink: return "Create Quick Link"
        case .qrCode: return "Generate QR Code"
        case .translation: return "Enter Translation"
        }
    }
}
