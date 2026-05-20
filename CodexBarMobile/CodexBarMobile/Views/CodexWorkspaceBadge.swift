import CodexBarSync
import SwiftUI

/// Codex workspace + weekly pace badge on the Codex detail page. Only
/// rendered when `ProviderUsageSnapshot.codexWorkspace` is non-nil —
/// today Mac doesn't yet populate this lane (see SyncCoordinator
/// `mapCodexWorkspace` stub), so the view stays dormant. The hook is
/// in place so once Mac lands the workspace/pace plumbing the badge
/// lights up without an iOS rebuild.
struct CodexWorkspaceBadge: View {
    let context: SyncCodexWorkspaceContext
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = context.workspaceName, !name.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if let label = context.weeklyPaceLabel, !label.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: self.paceIconName)
                        .font(.caption)
                        .foregroundStyle(self.paceColor)
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(self.paceColor)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("codex-workspace-badge")
    }

    private var paceIconName: String {
        guard let delta = context.weeklyPaceDelta else { return "speedometer" }
        if delta > 0.05 { return "arrow.up.circle.fill" }
        if delta < -0.05 { return "arrow.down.circle.fill" }
        return "equal.circle.fill"
    }

    private var paceColor: Color {
        guard let delta = context.weeklyPaceDelta else { return .secondary }
        if delta > 0.05 { return .orange }
        if delta < -0.05 { return .green }
        return self.tintColor
    }
}

#Preview {
    VStack(spacing: 12) {
        CodexWorkspaceBadge(
            context: SyncCodexWorkspaceContext(
                workspaceID: "ws-acme-prod",
                workspaceName: "Acme Production",
                weeklyPaceDelta: 0.12,
                weeklyPaceLabel: "+12% ahead of pace",
                updatedAt: Date()),
            tintColor: .purple)
        CodexWorkspaceBadge(
            context: SyncCodexWorkspaceContext(
                workspaceID: "ws-personal",
                workspaceName: "Personal",
                weeklyPaceDelta: -0.08,
                weeklyPaceLabel: "-8% under pace",
                updatedAt: Date()),
            tintColor: .purple)
    }
    .padding()
}
