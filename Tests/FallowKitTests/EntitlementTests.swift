import Foundation
import Testing

/// The sandbox Fallow ships with, in both builds: the App Store build signs with these too.
@Suite struct EntitlementTests {
    @Test func sandboxAllowsOnlyChosenFilesAndPrinting() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fallow.entitlements")
        let entitlements = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Bool])
        #expect(entitlements == [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.files.user-selected.read-write": true,
            "com.apple.security.print": true,
        ])
    }
}
