import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Mobile release notes catalog")
struct MobileReleaseNotesCatalogTests {
    @Test
    func `catalog is non-empty with latest release first`() {
        let versions = MobileReleaseNotesCatalog.versions

        #expect(!versions.isEmpty)
        #expect(versions.first?.version == "1.11.3")
        #expect(versions.first?.status == String(localized: "Latest"))
        #expect(versions.count { $0.status == String(localized: "Latest") } == 1)
    }

    @Test
    func `versions are unique and descending`() {
        let versions = MobileReleaseNotesCatalog.versions.map(\.version)
        let unique = Set(versions)

        #expect(unique.count == versions.count)
        #expect(versions == versions.sorted(by: Self.versionDescending))
    }

    @Test
    func `entries have non-empty content`() {
        for version in MobileReleaseNotesCatalog.versions {
            #expect(!version.version.isEmpty)
            #expect(!version.summary.isEmpty)
            #expect(!version.sections.isEmpty)
            for section in version.sections {
                #expect(!section.title.isEmpty)
                #expect(!section.items.isEmpty)
                for item in section.items {
                    #expect(!item.isEmpty)
                }
            }
        }
    }

    @Test
    func `catalog strings exist in Localizable.xcstrings`() throws {
        let catalog = try Self.localizationCatalog()
        let strings = Set(catalog.strings.keys)

        for value in Self.catalogStrings() {
            #expect(strings.contains(value), "Missing release-note localization key: \(value)")
        }
    }

    private static func versionDescending(_ lhs: String, _ rhs: String) -> Bool {
        self.versionComponents(lhs).lexicographicallyPrecedes(self.versionComponents(rhs)) == false
            && self.versionComponents(lhs) != self.versionComponents(rhs)
    }

    private static func versionComponents(_ value: String) -> [Int] {
        value
            .split(separator: " ")
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
    }

    private static func catalogStrings() -> [String] {
        MobileReleaseNotesCatalog.versions.flatMap { version in
            [version.status, version.summary]
                + version.sections.flatMap { [$0.title] + $0.items }
        }
        .filter { !$0.isEmpty }
    }

    private static func localizationCatalog() throws -> StringCatalog {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        let catalogURL = url.appendingPathComponent("CodexBarMobile/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(StringCatalog.self, from: data)
    }
}

private struct StringCatalog: Decodable {
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {}
