import Foundation

struct ApplicationRecord: Hashable, Identifiable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let url: URL

    var id: String { url.path }

    var searchableName: String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }
}
