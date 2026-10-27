import Foundation
import Testing
@testable import FlintCore

struct ApplicationDiscoveryTests {
    @Test func scansCategoriesDeduplicatesAndSkipsNestedHelpers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: root.appendingPathComponent("Utilities/Terminal.app"), name: "Terminal", id: "test.terminal")
        try makeApp(at: root.appendingPathComponent("Other Terminal.app"), name: "Other Terminal", id: "test.terminal")
        try makeApp(at: root.appendingPathComponent("Browser.app"), name: "Browser", id: "test.browser")
        try makeApp(at: root.appendingPathComponent("Browser.app/Contents/Helper.app"), name: "Helper", id: "test.helper")
        let apps = ApplicationDiscovery.discover(in: [root, root.appendingPathComponent("Missing")])
        #expect(apps.count == 2)
        #expect(apps.first?.name == "Browser")
        #expect(!apps.contains { $0.name == "Helper" })
    }

    @Test func missingDirectoryReturnsEmptyList() {
        #expect(ApplicationDiscovery.discover(in: [URL(fileURLWithPath: "/nonexistent/\(UUID())")]).isEmpty)
    }

    @Test func blankMetadataFallsBackToApplicationFilename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: root.appendingPathComponent("YUVViewer.app"), name: "  ", id: "test.blank-name")
        #expect(ApplicationDiscovery.discover(in: [root]).first?.name == "YUVViewer")
    }

    private func makeApp(at url: URL, name: String, id: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleName": name, "CFBundleIdentifier": id,
            "CFBundleExecutable": "stub", "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data().write(to: contents.appendingPathComponent("MacOS/stub"))
    }
}
