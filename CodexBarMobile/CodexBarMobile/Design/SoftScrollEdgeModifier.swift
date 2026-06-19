import SwiftUI

/// Applies `.scrollEdgeEffectStyle(.soft)` on iOS 26+, no-op on older systems.
struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
