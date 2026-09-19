import Foundation
import Testing

/// Keeps the String Catalogs honest.
///
/// Reads the catalogs and the view sources from the repository, so an
/// untranslated string, a placeholder that a translation dropped, or a new
/// literal that never reached a catalog fails here rather than shipping in
/// English on a German system.
@Suite("Localization catalogs")
struct LocalizationCatalogTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private struct Catalog {
        let strings: [String: [String: Any]]

        init(_ relativePath: String) throws {
            let data = try Data(contentsOf: LocalizationCatalogTests.root.appendingPathComponent(relativePath))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            strings = (json?["strings"] as? [String: [String: Any]]) ?? [:]
        }

        func localization(_ key: String, _ language: String) -> [String: Any]? {
            (strings[key]?["localizations"] as? [String: Any])?[language] as? [String: Any]
        }

        /// Every value a language provides for a key: the single string, or
        /// each plural form.
        func values(_ key: String, _ language: String) -> [String] {
            guard let localization = localization(key, language) else { return [] }
            if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                return [value]
            }
            if let variations = localization["variations"] as? [String: Any],
                let plural = variations["plural"] as? [String: Any]
            {
                return plural.values.compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
                    .compactMap { $0["value"] as? String }
            }
            return []
        }
    }

    private static let catalogPaths = [
        "Sources/OpenSwitchr/Localizable.xcstrings",
        "Sources/OpenSwitchrUI/UI.xcstrings",
    ]

    private static func specifiers(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|ld|d|@|f|s)")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).map { String(text[Range($0.range, in: text)!]) }.sorted()
    }

    @Test("Every entry has a translated German value")
    func everyEntryIsTranslated() throws {
        for path in Self.catalogPaths {
            let catalog = try Catalog(path)
            #expect(!catalog.strings.isEmpty, "\(path) is empty")
            for key in catalog.strings.keys {
                let values = catalog.values(key, "de")
                #expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty }, "\(path): no German value for “\(key)”")
            }
        }
    }

    @Test("A translation keeps every placeholder the source has")
    func placeholdersSurvive() throws {
        for path in Self.catalogPaths {
            let catalog = try Catalog(path)
            for key in catalog.strings.keys where catalog.localization(key, "en") == nil {
                let expected = Self.specifiers(in: key)
                for value in catalog.values(key, "de") {
                    #expect(
                        Self.specifiers(in: value) == expected,
                        "\(path): “\(key)” → “\(value)” changes its placeholders")
                }
            }
        }
    }

    @Test("Plural entries provide one and other in both languages, each with the count")
    func pluralsAreComplete() throws {
        for path in Self.catalogPaths {
            let catalog = try Catalog(path)
            for (key, entry) in catalog.strings {
                guard let localizations = entry["localizations"] as? [String: Any],
                    localizations.values.contains(where: { ($0 as? [String: Any])?["variations"] != nil })
                else { continue }
                for language in ["en", "de"] {
                    let variations =
                        (catalog.localization(key, language)?["variations"] as? [String: Any])?["plural"]
                        as? [String: Any]
                    #expect(
                        variations?["one"] != nil && variations?["other"] != nil,
                        "\(path): “\(key)” lacks a plural form in \(language)")
                    for value in catalog.values(key, language) {
                        #expect(
                            value.contains("%lld"),
                            "\(path): “\(key)” [\(language)] plural form has no count: “\(value)”")
                    }
                }
            }
        }
    }

    @Test("The product name and the modifier symbols are never translated away")
    func namesAndSymbolsSurvive() throws {
        for path in Self.catalogPaths {
            let catalog = try Catalog(path)
            for key in catalog.strings.keys {
                for token in ["OpenSwitchr", "⌘", "⌥", "⌃"] where key.contains(token) {
                    for value in catalog.values(key, "de") {
                        #expect(value.contains(token), "\(path): “\(key)” lost “\(token)” in “\(value)”")
                    }
                }
            }
        }
    }

    /// Plain literals handed to a SwiftUI view initialiser, which SwiftUI looks up
    /// in the catalog. Interpolated ones have a generated key and are covered by
    /// the entries above; this catches the ordinary case of a new string that was
    /// never added.
    private static func literals(in relativeDirectory: String, matching pattern: String) throws -> Set<String> {
        let directory = root.appendingPathComponent(relativeDirectory)
        let regex = try NSRegularExpression(pattern: pattern)
        var found = Set<String>()
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                found.insert(String(text[range]))
            }
        }
        return found
    }

    @Test("Every plain literal in the app's views has a catalog entry")
    func appLiteralsAreInTheCatalog() throws {
        let catalog = try Catalog("Sources/OpenSwitchr/Localizable.xcstrings")
        let literals = try Self.literals(
            in: "Sources/OpenSwitchr",
            matching: #"(?:Text|Label|Toggle|Picker|Button|Section|LabeledContent|Stepper|TextField)\("([^"\\]+)""#
        )
        // The product name is deliberately not translated, and an interpolated
        // literal has a generated key.
        #expect(literals.count > 30, "the scan found almost nothing, so it proves nothing")
        let exempt: Set<String> = ["OpenSwitchr"]
        let missing = literals.filter {
            $0.range(of: "\\(") == nil && !exempt.contains($0) && catalog.strings[$0] == nil
        }
        #expect(missing.isEmpty, "Not in Localizable.xcstrings: \(missing.sorted())")
    }

    @Test("Every UI-table lookup in the shared views has a catalog entry")
    func uiLiteralsAreInTheCatalog() throws {
        let catalog = try Catalog("Sources/OpenSwitchrUI/UI.xcstrings")
        let literals = try Self.literals(
            in: "Sources/OpenSwitchrUI",
            matching: #"String\(localized: "([^"\\]+)", table: "UI""#
        )
        let keys = Set(
            literals.map { $0.replacingOccurrences(of: #"\([^)]*\)"#, with: "%@", options: .regularExpression) })
        let missing = keys.filter { catalog.strings[$0] == nil }
        #expect(!keys.isEmpty)
        #expect(missing.isEmpty, "Not in UI.xcstrings: \(missing.sorted())")
    }

    /// The other half of keeping a catalog complete: an entry nothing looks up any
    /// more is a dead translation that survives every removal of its string.
    ///
    /// A key counts as used when its text appears inside a string literal
    /// anywhere under `Sources`, with each format specifier standing for the
    /// interpolation that produces it. That is deliberately generous, since a
    /// key can be reached through a `title` property in Core as well as a view.
    @Test("No catalog entry is orphaned: every key is still used by the code")
    func noCatalogEntryIsOrphaned() throws {
        let sources = Self.root.appendingPathComponent("Sources")
        var code = ""
        if let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "swift" {
                code += try String(contentsOf: file, encoding: .utf8)
            }
        }
        #expect(code.count > 10_000, "the scan read almost nothing, so it proves nothing")

        var orphans: [String] = []
        for path in Self.catalogPaths {
            let catalog = try Catalog(path)
            #expect(!catalog.strings.isEmpty)
            for key in catalog.strings.keys where !Self.isUsed(key, in: code) {
                orphans.append("\(path): \(key)")
            }
        }
        #expect(orphans.isEmpty, "Catalog entries no code refers to: \(orphans.sorted())")
    }

    private static func isUsed(_ key: String, in code: String) -> Bool {
        let specifier = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|ld|d|@|f|s)")
        var pattern = ""
        var cursor = key.startIndex
        for match in specifier.matches(in: key, range: NSRange(key.startIndex..., in: key)) {
            let matched = Range(match.range, in: key)!
            pattern += NSRegularExpression.escapedPattern(for: literalForm(String(key[cursor..<matched.lowerBound])))
            pattern += #"[^"\n]*"#
            cursor = matched.upperBound
        }
        pattern += NSRegularExpression.escapedPattern(for: literalForm(String(key[cursor...])))
        return code.range(of: pattern, options: .regularExpression) != nil
    }

    /// How a key's text is spelled inside Swift source, where quotes and backslashes are escaped.
    private static func literalForm(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
