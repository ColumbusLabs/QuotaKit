import SwiftUI

struct QKCardBackgroundModifier: ViewModifier {
    @Environment(\.quotaKitTheme) private var theme
    var elevation: QKElevation = .surface
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(self.theme.fill(for: self.elevation), in: RoundedRectangle(
                cornerRadius: self.cornerRadius,
                style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .strokeBorder(self.theme.border, lineWidth: 1)
            }
    }
}

extension View {
    func qkCardBackground(elevation: QKElevation = .surface, cornerRadius: CGFloat = 14) -> some View {
        self.modifier(QKCardBackgroundModifier(elevation: elevation, cornerRadius: cornerRadius))
    }
}

struct QKSurfaceCard<Content: View>: View {
    @Environment(\.quotaKitTheme) private var theme
    var elevation: QKElevation = .surface
    var accentColor: Color?
    var cornerRadius: CGFloat = 16
    var dashedBorder: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        self.content()
            .background {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .fill(self.theme.fill(for: self.elevation))

                    if let accent = self.accentColor {
                        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.14), accent.opacity(0.02), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay(alignment: .leading) {
                if let accent = self.accentColor {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.vertical, 12)
                        .padding(.leading, 0)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .strokeBorder(
                        self.dashedBorder ? self.theme.border : self.theme.border,
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: self.dashedBorder ? [5, 4] : []))
            }
    }
}
