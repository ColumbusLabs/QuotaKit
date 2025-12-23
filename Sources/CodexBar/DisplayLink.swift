import AppKit
import Observation
import QuartzCore

/// Minimal CADisplayLink driver built on macOS 15's NSScreen.displayLink replacement.
/// Publishes ticks on the main thread at the requested frame rate.
@MainActor
@Observable
final class DisplayLinkDriver {
    // Published counter used to drive SwiftUI updates.
    var tick: Int = 0
    private var link: CADisplayLink?

    func start(fps: Double = 12) {
        guard self.link == nil, let screen = NSScreen.main else { return }
        let displayLink = screen.displayLink(target: self, selector: #selector(self.step))
        let rate = Float(fps)
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: rate,
            maximum: rate,
            preferred: rate)
        displayLink.add(to: .main, forMode: .common)
        self.link = displayLink
    }

    func stop() {
        self.link?.invalidate()
        self.link = nil
    }

    @objc private func step(_: CADisplayLink) {
        // Safe on main runloop; drives SwiftUI updates.
        self.tick &+= 1
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
}
