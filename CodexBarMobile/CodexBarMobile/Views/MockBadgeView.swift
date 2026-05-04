import SwiftUI

/// Compact `MOCK` pill shown next to a provider's name when its data is
/// synthetic (per `MockProviderDetector`). Purple capsule, semantic-bold
/// text, never localized (the literal "MOCK" is industry-standard
/// engineering shorthand and stays as-is across every locale).
///
/// **Visual contract** (iOS 1.5.2+):
/// - Tinted purple capsule (Color.purple — system-defined; respects
///   light/dark mode + accessibility contrast).
/// - 9pt monospaced bold text — small enough to fit in the card header
///   without dwarfing the provider name; monospace gives it an
///   "engineering tag" appearance distinct from user-facing labels.
/// - 4pt horizontal padding + 2pt vertical — Apple-standard pill geometry.
/// - Always renders on top of any background; uses `.foregroundStyle` so
///   it inverts cleanly to white text on the purple capsule.
struct MockBadgeView: View {
    var body: some View {
        Text(verbatim: "MOCK")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.purple, in: Capsule())
            .accessibilityLabel(Text("Mock data badge"))
    }
}

#Preview("MOCK Badge") {
    HStack {
        Text("Codex (Alice · Mock)")
            .font(.title3.bold())
        MockBadgeView()
    }
    .padding()
}
