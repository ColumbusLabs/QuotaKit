import Foundation
import Testing

/// Lexical tripwire for environment dictionary declarations, including optional and multiline spellings.
/// Stored process environments must opt into the redacting wrapper before they can appear in diagnostics.
struct ProcessEnvironmentStorageTests {
    @Test
    func `shipped environment dictionary storage uses the redacting wrapper`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        var usedExceptions: Set<String> = []
        for directory in ["Sources", "WidgetExtension"] {
            let enumerator = try #require(FileManager.default.enumerator(
                at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let path = String(url.path.dropFirst(root.path.count + 1))
                guard path != "Sources/CodexBarCore/ProcessEnvironment.swift" else { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                for declaration in try Self.unprotectedDeclarations(in: source) {
                    if let exception = Self.transientLocals[path], exception == declaration {
                        #expect(usedExceptions.insert(path).inserted, "Duplicate transient exception: \(path)")
                    } else {
                        Issue.record("Unprotected environment storage: \(path): \(declaration)")
                    }
                }
            }
        }
        #expect(usedExceptions == Set(Self.transientLocals.keys), "Remove stale transient exceptions")
    }

    @Test
    func `scanner separates stored properties from function and closure locals`() throws {
        let source = #"""
        let globalEnvironment: [String: String] = [:]
        struct Example {
            // An unmatched close brace and a declaration example in a comment are not code.
            // } let commentEnvironment: [String: String] = [:]
            let scopeString = "{"
            let multilineScopeString = """
                let stringEnvironment: [String: String] = [:]
                }
                """
            let rawScopeString = #"}"#
            let interpolatedScopeString = "value \(String(describing: "}"))"
            let environment: [String: String]
            private var baseEnvironment:
                [String: String]?
            var env: Dictionary<String, String> = [:]
            @ProcessEnvironment private var protectedEnvironment: [String: String]
            @ProcessEnvironment
            public private(set) var anotherEnvironment: [String: String]?
            @ProcessEnvironment
            private var multilineProtectedEnvironment:
                [String: String]?
            var computedEnvironment: [String: String] { [:] }
            var anotherComputedEnvironment: [String: String]
            { [:] }
            var observedEnvironment: [String: String] { didSet {} }
            var initializedEnvironment: [String: String] = { [:] }()
            lazy var lazyEnvironment: [String: String] = [:]
            nonisolated(unsafe) static var sharedEnvironment: [String: String] = [:]
            func run(environment: [String: String]) {}
            func localStorage() {
                let localEnvironment: [String: String] = [:]
                let closure = {
                    var closureEnvironment: Dictionary<String, String> = [:]
                    _ = closureEnvironment
                }
                _ = (localEnvironment, closure)
            }
            class NestedClass {
                let nestedClassEnvironment: [String: String]
                class func localStorage() {
                    let classMethodEnvironment: [String: String] = [:]
                    _ = classMethodEnvironment
                }
            }
            struct Nested {
                let nestedEnvironment: [String: String]
            }
        }
        func topLevelFunction() {
            let functionEnvironment: [String: String] = [:]
            _ = functionEnvironment
        }
        """#
        #expect(try Self.unprotectedDeclarations(in: source) == [
            "let globalEnvironment: [String: String] = [:]",
            "let environment: [String: String]",
            "private var baseEnvironment: [String: String]?",
            "var env: Dictionary<String, String> = [:]",
            "var observedEnvironment: [String: String] { didSet {} }",
            "var initializedEnvironment: [String: String] = { [:] }()",
            "lazy var lazyEnvironment: [String: String] = [:]",
            "nonisolated(unsafe) static var sharedEnvironment: [String: String] = [:]",
            "let nestedClassEnvironment: [String: String]",
            "let nestedEnvironment: [String: String]",
        ])
    }

    private static let transientLocals: [String: String] = [:]

    private static func unprotectedDeclarations(in source: String) throws -> [String] {
        let scanned = Self.scanScopes(in: source)
        let pattern = #"(?m)^[\t ]*((?:@\w+(?:\([^\n]*\))?\s+)*"# +
            #"(?:(?:public|private|internal|fileprivate|package|static|lazy|nonisolated|final)"# +
            #"(?:\((?:set|unsafe)\))?\s+)*"# +
            #"(?:let|var)\s+\w*[Ee]nv\w*\s*:\s*"# +
            #"(?:\[\s*String\s*:\s*String\s*\]|Dictionary\s*<\s*String\s*,\s*String\s*>)\??[^\n]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(in: scanned.code, range: NSRange(scanned.code.startIndex..., in: scanned.code))
            .compactMap { match in
                let declarationLocation = match.range(at: 1).location
                guard scanned.isStoredScope(atUTF16Offset: declarationLocation),
                      let range = Range(match.range(at: 1), in: scanned.code)
                else {
                    return nil
                }
                let declaration = String(scanned.code[range])
                guard !declaration.contains("@ProcessEnvironment") else { return nil }
                // Getters are transient; observers and initializer closures still have stored backing values.
                if !declaration.contains("=") {
                    let body = declaration.firstIndex(of: "{").map { String(declaration[$0...]) }
                        ?? String(scanned.code[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if body.hasPrefix("{"),
                       body.range(of: #"^\{\s*(?:didSet|willSet)\b"#, options: .regularExpression) == nil
                    {
                        return nil
                    }
                }
                return declaration.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
    }

    private struct ScopeScan {
        let code: String
        let storedScopeOffsets: [Bool]

        func isStoredScope(atUTF16Offset offset: Int) -> Bool {
            guard self.storedScopeOffsets.indices.contains(offset) else { return false }
            return self.storedScopeOffsets[offset]
        }
    }

    private static func scanScopes(in source: String) -> ScopeScan {
        // This is a focused lexical scanner rather than a Swift parser. It handles comments and
        // ordinary/raw strings (including nested string interpolation); slash regex literals are
        // outside its scope and can contain braces that affect this tripwire.
        var codeUnits = Array(source.utf16)
        Self.maskCommentsAndStrings(in: &codeUnits)
        let code = String(decoding: codeUnits, as: UTF16.self)
        var storedScopeOffsets = Array(repeating: true, count: codeUnits.count)
        var scopes: [Bool] = []
        var declarationHeaderStart = 0

        for offset in codeUnits.indices {
            storedScopeOffsets[offset] = scopes.last ?? true
            switch codeUnits[offset] {
            case 0x7B: // {
                scopes.append(Self.opensTypeScope(in: codeUnits[declarationHeaderStart..<offset]))
                declarationHeaderStart = offset + 1
            case 0x7D: // }
                if !scopes.isEmpty { scopes.removeLast() }
                declarationHeaderStart = offset + 1
            case 0x3B: // ;
                declarationHeaderStart = offset + 1
            default:
                break
            }
        }
        return ScopeScan(code: code, storedScopeOffsets: storedScopeOffsets)
    }

    private static func opensTypeScope(in header: ArraySlice<UInt16>) -> Bool {
        let units = Array(header)
        var words: [String] = []
        var offset = 0
        while offset < units.count {
            guard Self.isIdentifierStart(units[offset]) else {
                offset += 1
                continue
            }
            let start = offset
            offset += 1
            while offset < units.count, Self.isIdentifierContinuation(units[offset]) {
                offset += 1
            }
            words.append(String(decoding: units[start..<offset], as: UTF16.self))
        }
        for (index, word) in words.enumerated() {
            if ["struct", "enum", "actor", "extension"].contains(word) { return true }
            guard word == "class" else { continue }
            let suffix = words.dropFirst(index + 1)
            // `class func` and `class var` are member modifiers, not type declarations.
            if suffix.contains("func") || suffix.contains("var") || suffix.contains("subscript") { continue }
            return true
        }
        return false
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F
    }

    private static func isIdentifierContinuation(_ unit: UInt16) -> Bool {
        self.isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39)
    }

    private static func maskCommentsAndStrings(in units: inout [UInt16]) {
        var offset = 0
        while offset < units.count {
            if Self.has(units, offset, [0x2F, 0x2F]) {
                let start = offset
                offset += 2
                while offset < units.count, units[offset] != 0x0A, units[offset] != 0x0D {
                    offset += 1
                }
                Self.mask(units: &units, range: start..<offset)
            } else if Self.has(units, offset, [0x2F, 0x2A]) {
                let start = offset
                offset = Self.skipBlockComment(in: units, from: offset)
                Self.mask(units: &units, range: start..<offset)
            } else if let stringStart = Self.stringStart(in: units, at: offset) {
                let end = Self.skipString(in: units, start: offset, rawHashCount: stringStart.rawHashCount)
                Self.mask(units: &units, range: offset..<end)
                offset = end
            } else {
                offset += 1
            }
        }
    }

    private static func stringStart(in units: [UInt16], at offset: Int) -> (rawHashCount: Int, quoteOffset: Int)? {
        var quoteOffset = offset
        while quoteOffset < units.count, units[quoteOffset] == 0x23 {
            quoteOffset += 1
        }
        guard quoteOffset < units.count, units[quoteOffset] == 0x22 else { return nil }
        return (quoteOffset - offset, quoteOffset)
    }

    private static func skipString(in units: [UInt16], start: Int, rawHashCount: Int) -> Int {
        guard let stringStart = Self.stringStart(in: units, at: start) else { return start + 1 }
        let quoteOffset = stringStart.quoteOffset
        let isMultiline = Self.has(units, quoteOffset, [0x22, 0x22, 0x22])
        let quoteCount = isMultiline ? 3 : 1
        var offset = quoteOffset + quoteCount

        while offset < units.count {
            if units[offset] == 0x5C, let interpolationStart = Self.interpolationStart(
                in: units, at: offset, rawHashCount: rawHashCount)
            {
                offset = Self.skipInterpolation(in: units, openingParen: interpolationStart)
                continue
            }
            if units[offset] == 0x5C, rawHashCount > 0,
               let escapedQuoteEnd = Self.rawEscapedQuoteEnd(
                   in: units, at: offset, rawHashCount: rawHashCount, quoteCount: quoteCount)
            {
                offset = escapedQuoteEnd
                continue
            }
            if rawHashCount == 0, units[offset] == 0x5C {
                offset = min(offset + 2, units.count)
                continue
            }
            if Self.has(units, offset, Array(repeating: 0x22, count: quoteCount)),
               Self.has(units, offset + quoteCount, Array(repeating: 0x23, count: rawHashCount))
            {
                return offset + quoteCount + rawHashCount
            }
            offset += 1
        }
        return units.count
    }

    private static func rawEscapedQuoteEnd(
        in units: [UInt16],
        at offset: Int,
        rawHashCount: Int,
        quoteCount: Int) -> Int?
    {
        var quoteOffset = offset + 1
        for _ in 0..<rawHashCount {
            guard quoteOffset < units.count, units[quoteOffset] == 0x23 else { return nil }
            quoteOffset += 1
        }
        return Self.has(units, quoteOffset, Array(repeating: 0x22, count: quoteCount))
            ? quoteOffset + quoteCount
            : nil
    }

    private static func interpolationStart(in units: [UInt16], at offset: Int, rawHashCount: Int) -> Int? {
        var parenOffset = offset + 1
        for _ in 0..<rawHashCount {
            guard parenOffset < units.count, units[parenOffset] == 0x23 else { return nil }
            parenOffset += 1
        }
        return parenOffset < units.count && units[parenOffset] == 0x28 ? parenOffset : nil
    }

    private static func skipInterpolation(in units: [UInt16], openingParen: Int) -> Int {
        var depth = 1
        var offset = openingParen + 1
        while offset < units.count {
            if Self.has(units, offset, [0x2F, 0x2F]) {
                offset += 2
                while offset < units.count, units[offset] != 0x0A, units[offset] != 0x0D {
                    offset += 1
                }
            } else if Self.has(units, offset, [0x2F, 0x2A]) {
                offset = Self.skipBlockComment(in: units, from: offset)
            } else if let stringStart = Self.stringStart(in: units, at: offset) {
                offset = Self.skipString(in: units, start: offset, rawHashCount: stringStart.rawHashCount)
            } else if units[offset] == 0x28 {
                depth += 1
                offset += 1
            } else if units[offset] == 0x29 {
                depth -= 1
                offset += 1
                if depth == 0 { return offset }
            } else {
                offset += 1
            }
        }
        return units.count
    }

    private static func skipBlockComment(in units: [UInt16], from start: Int) -> Int {
        var depth = 1
        var offset = start + 2
        while offset < units.count, depth > 0 {
            if Self.has(units, offset, [0x2F, 0x2A]) {
                depth += 1
                offset += 2
            } else if Self.has(units, offset, [0x2A, 0x2F]) {
                depth -= 1
                offset += 2
            } else {
                offset += 1
            }
        }
        return offset
    }

    private static func has(_ units: [UInt16], _ offset: Int, _ pattern: [UInt16]) -> Bool {
        guard offset >= 0, offset + pattern.count <= units.count else { return false }
        return units[offset..<(offset + pattern.count)].elementsEqual(pattern)
    }

    private static func mask(units: inout [UInt16], range: Range<Int>) {
        for offset in range where units[offset] != 0x0A && units[offset] != 0x0D {
            units[offset] = 0x20
        }
    }
}
