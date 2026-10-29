import Foundation

enum SystemAction: String, CaseIterable, Hashable, Identifiable, Sendable {
    case ejectAllDisks
    case emptyTrash
    case showDesktop

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ejectAllDisks: return "Eject All Disks"
        case .emptyTrash: return "Empty Trash"
        case .showDesktop: return "Show Desktop"
        }
    }

    var symbolName: String {
        switch self {
        case .ejectAllDisks: return "eject"
        case .emptyTrash: return "trash"
        case .showDesktop: return "macwindow"
        }
    }

    var requiresConfirmation: Bool { self == .emptyTrash }
}
