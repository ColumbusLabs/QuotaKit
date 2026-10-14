import Testing
@testable import CodexBar

@MainActor
struct MenuCardLiveSubtitleTests {
    @Test
    func `error joins stale notice only when card has no reserved stale row`() {
        let error = MenuCardLiveSubtitle(
            text: "Request failed",
            style: .error,
            lastKnownUsageText: "Showing last-known usage.")

        let compact = error.displayed(reservesStaleRow: false)
        #expect(compact.subtitle == "Request failed Showing last-known usage.")
        #expect(compact.staleRow == nil)

        let reserved = error.displayed(reservesStaleRow: true)
        #expect(reserved.subtitle == "Request failed")
        #expect(reserved.staleRow == "Showing last-known usage.")
    }

    @Test
    func `recovery hides text while retaining a reserved row`() {
        let recovered = MenuCardLiveSubtitle(text: "Updated just now", style: .info)
            .displayed(reservesStaleRow: true)
        #expect(recovered.subtitle == "Updated just now")
        #expect(recovered.staleRow == nil)
    }
}
