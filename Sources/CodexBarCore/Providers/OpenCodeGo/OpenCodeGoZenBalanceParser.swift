import Foundation

enum OpenCodeGoZenBalanceParser {
    static func parse(text: String) -> Double? {
        if let value = self.parseJSON(text: text) {
            return value
        }
        let localizedPattern = [
            #"(?i)(?:current\s+balance|zen\s+balance|現在の残高)"#,
            #"[^$]{0,80}\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#,
        ].joined()
        if let value = self.extractDollarValue(pattern: localizedPattern, text: text) {
            return value
        }
        let nearbyPattern = #"(?i)(?:balance|残高)[\s\S]{0,120}?\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#
        return self.extractDollarValue(pattern: nearbyPattern, text: text)
    }

    private static func parseJSON(text: String) -> Double? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        return self.findBalanceValue(in: object, path: [])
    }

    private static func findBalanceValue(in object: Any, path: [String]) -> Double? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                let nextPath = path + [key]
                if self.isExplicitBalanceAmountKey(key),
                   let number = self.doubleValue(from: value)
                {
                    return number
                }
                if let found = self.findBalanceValue(in: value, path: nextPath) {
                    return found
                }
            }
            return nil
        }
        if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                if let found = self.findBalanceValue(in: value, path: path + ["[\(index)]"]) {
                    return found
                }
            }
        }
        return nil
    }

    private static func isExplicitBalanceAmountKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return [
            "zenbalance",
            "zencurrentbalance",
            "currentbalance",
            "currentbalanceusd",
            "balanceusd",
            "usdbalance",
        ].contains(normalized)
    }

    private static func extractDollarValue(pattern: String, text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[range].replacingOccurrences(of: ",", with: ""))
    }

    private static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case is Bool:
            nil
        case let number as Double:
            number
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(
                string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ""))
        default:
            nil
        }
    }
}
