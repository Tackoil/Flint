import Foundation

enum LauncherItem: Hashable, Identifiable, Sendable {
    case application(ApplicationRecord)
    case action(SystemAction)
    case quickLink(QuickLink)
    case script(ScriptCommand)
    case scriptCommands
    case createQuickLink
    case translation
    case qrCode

    var id: String {
        switch self {
        case .application(let application): return "application:\(application.id)"
        case .action(let action): return "action:\(action.id)"
        case .quickLink(let link): return "quickLink:\(link.id)"
        case .script(let script): return "script:\(script.id)"
        case .scriptCommands: return "scriptCommands"
        case .createQuickLink: return "createQuickLink"
        case .qrCode: return "qrCode"
        case .translation: return "translation"
        }
    }

    var usageID: String {
        if case .application(let app) = self, let bundleIdentifier = app.bundleIdentifier {
            return "bundle:\(bundleIdentifier)"
        }
        return id
    }

    var name: String {
        switch self {
        case .application(let application): return application.name
        case .action(let action): return action.name
        case .quickLink(let link): return link.name
        case .script(let script): return script.name
        case .scriptCommands: return "Script Commands"
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
        case .script: return "Script"
        case .scriptCommands: return "Settings"
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
        case .script: return "Run Script"
        case .scriptCommands: return "Manage Scripts"
        case .createQuickLink: return "Create Quick Link"
        case .qrCode: return "Generate QR Code"
        case .translation: return "Enter Translation"
        }
    }
}
