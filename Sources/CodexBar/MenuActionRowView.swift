import SwiftUI

struct MenuActionRowView: View {
    let title: String
    let systemImageName: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let systemImageName {
                Image(systemName: systemImageName)
                    .imageScale(.medium)
                    .frame(width: 18, alignment: .center)
            }
            Text(self.title)
        }
        .font(.body)
        .foregroundStyle(MenuHighlightStyle.primary(self.isHovering))
        .padding(.vertical, 2)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if self.isHovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MenuHighlightStyle.selectionBackground(true))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
        }
        .onHover { hovering in
            self.isHovering = hovering
        }
        .onTapGesture {
            self.action()
        }
    }
}
