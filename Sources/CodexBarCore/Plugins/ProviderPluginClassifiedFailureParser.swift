import Foundation

enum ProviderPluginClassifiedFailureParser {
    private static let markerV1 = "__CODEXBAR_FAILURE__:"
    private static let markerV2 = "__CODEXBAR_FAILURE_V2__:"

    static func error(from message: String) -> ProviderFetchClassifiedError? {
        if message.hasPrefix(self.markerV2) {
            return self.parseV2(String(message.dropFirst(self.markerV2.count)))
        }
        guard message.hasPrefix(self.markerV1) else { return nil }
        let payload = message.dropFirst(self.markerV1.count)
        guard let separator = payload.firstIndex(of: ":"),
              let kind = ProviderFetchClassifiedError.Kind(rawValue: String(payload[..<separator]))
        else { return nil }
        return ProviderFetchClassifiedError(
            kind: kind,
            message: String(payload[payload.index(after: separator)...]))
    }

    private static func parseV2(_ payload: String) -> ProviderFetchClassifiedError? {
        guard let kindSeparator = payload.firstIndex(of: ":"),
              let kind = ProviderFetchClassifiedError.Kind(rawValue: String(payload[..<kindSeparator]))
        else { return nil }
        let retryAndMessage = payload[payload.index(after: kindSeparator)...]
        guard let retrySeparator = retryAndMessage.firstIndex(of: ":") else { return nil }
        let retryText = String(retryAndMessage[..<retrySeparator])
        let retryAfterSeconds = retryText.isEmpty ? nil : TimeInterval(retryText)
        guard retryText.isEmpty || retryAfterSeconds != nil else { return nil }
        return ProviderFetchClassifiedError(
            kind: kind,
            message: String(retryAndMessage[retryAndMessage.index(after: retrySeparator)...]),
            retryAfterSeconds: retryAfterSeconds)
    }
}
