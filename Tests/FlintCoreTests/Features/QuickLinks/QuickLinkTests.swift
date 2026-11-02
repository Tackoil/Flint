import Foundation
import Testing
@testable import FlintCore

struct QuickLinkTests {
    @Test func acceptsWebsitesDeeplinksAndFiles() throws {
        for destination in ["https://example.com/docs?a=1#intro", "slack://channel?team=T&id=C", "/tmp/My Folder", "~/Downloads"] {
            let link = QuickLink(name: "  My Link  ", link: " \(destination)\n")
            try link.validate()
            #expect(link.name == "My Link")
            #expect(try !link.resolvedURL().absoluteString.isEmpty)
        }
        #expect(try QuickLink(name: "Downloads", link: "~/Downloads").resolvedURL().path
                == NSHomeDirectory() + "/Downloads")
        #expect(try QuickLink(name: "File", link: "/tmp/My Folder").resolvedURL().path == "/tmp/My Folder")
    }

    @Test func rejectsMissingNamesAndIncompleteDestinations() {
        #expect(throws: (any Error).self) { try QuickLink(name: " ", link: "https://example.com").validate() }
        for destination in ["", "example.com", "relative/path", "https://", "https://example.com/a b", "https://example.com/{query", "javascript:alert(1)", "data:text/html,test"] {
            #expect(throws: (any Error).self) { try QuickLink(name: "Invalid", link: destination).validate() }
        }
    }

    @Test func encodesArgumentsWithoutChangingURLStructure() throws {
        let link = QuickLink(name: "Search", link: "https://example.com/search?q={query}&copy={query}#results")
        #expect(link.arguments.map(\.name) == ["query"])
        let url = try link.resolvedURL(values: ["{query}": "a &b=1/#?中文+%"])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(components.queryItems?.map(\.name) == ["q", "copy"])
        #expect(components.queryItems?.map(\.value) == ["a &b=1/#?中文+%", "a &b=1/#?中文+%"])
        #expect(components.fragment == "results")
    }

    @Test func supportsNamedAndRaycastArguments() throws {
        let link = QuickLink(name: "Repository", link: #"https://github.com/{argument name="Organization"}/{repo}?q={argument}"#)
        #expect(link.arguments.map(\.name) == ["Organization", "repo", "Query"])
        let url = try link.resolvedURL(values: [#"{argument name="Organization"}"#: "open ai", "{repo}": "flint/core", "{argument}": "a+b"])
        #expect(url.absoluteString == "https://github.com/open%20ai/flint%2Fcore?q=a%2Bb")
    }

    @Test func requiresEveryArgumentAndLimitsPromptSize() throws {
        let link = QuickLink(name: "Search", link: "https://example.com/{org}/{repo}")
        #expect(throws: (any Error).self) { try link.resolvedURL(values: ["{org}": "test"]) }
        #expect(throws: (any Error).self) { try link.resolvedURL(values: ["{org}": "test", "{repo}": "  "]) }
        let tooMany = QuickLink(name: "Many", link: "https://example.com/" + (0..<9).map { "{arg\($0)}" }.joined())
        #expect(throws: (any Error).self) { try tooMany.validate() }
    }

    @Test func fileArgumentsPreserveSpaces() throws {
        let link = QuickLink(name: "Project", link: "/tmp/{project}/README.md")
        #expect(try link.resolvedURL(values: ["{project}": "My Project"]).path == "/tmp/My Project/README.md")
    }

    @Test func persistsEditsAndDeletionWithoutChangingIdentity() throws {
        let suite = "FlintQuickLinkTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QuickLinkStore(defaults: defaults)
        #expect(store.links.isEmpty)
        var link = QuickLink(name: "Search", link: "https://example.com/?q={query}",
                             applicationURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        try store.save(link)
        #expect(QuickLinkStore(defaults: defaults).links == [link])
        link.name = "Updated Search"
        try store.save(link)
        #expect(store.links == [link])
        #expect(throws: (any Error).self) { try store.save(QuickLink(name: "", link: "invalid")) }
        #expect(store.links == [link])
        try store.remove(id: link.id)
        #expect(QuickLinkStore(defaults: defaults).links.isEmpty)
    }

    @Test func corruptStorageDoesNotCrash() {
        let suite = "FlintQuickLinkCorruptionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "quickLinks")
        #expect(QuickLinkStore(defaults: defaults).links.isEmpty)
    }

    @Test func quickLinksShareLauncherRanking() {
        let link = QuickLink(name: "Project Dashboard", link: "https://example.com")
        let items: [LauncherItem] = [.createQuickLink, .quickLink(link), .translation]
        #expect(ApplicationSearch.filter(items, query: "pd") == [.quickLink(link)])
        #expect(ApplicationSearch.filter(items, query: "create quick") == [.createQuickLink])
        #expect(LauncherItem.quickLink(link).buttonTitle == "Open Quick Link")
    }
}
