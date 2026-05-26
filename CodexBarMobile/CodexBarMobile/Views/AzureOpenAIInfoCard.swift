import CodexBarSync
import SwiftUI

/// Azure OpenAI deployment-info card (parity gap E).
///
/// Azure OpenAI is a deployment-validation provider (no usage %), so this shows
/// the validated endpoint, deployment, model, and API version. Renders only
/// when `SyncAzureOpenAIInfo` is present; older Mac payloads omit it and only
/// the deployment name reaches iOS via the generic loginMethod line.
struct AzureOpenAIInfoCard: View {
    let info: SyncAzureOpenAIInfo
    var tintColor: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(self.tintColor)
                Text("Deployment validated")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            self.infoRow(label: String(localized: "Endpoint"), value: self.info.endpointHost)
            self.infoRow(label: String(localized: "Deployment"), value: self.info.deploymentName)
            if let model = self.info.model, !model.isEmpty {
                self.infoRow(label: String(localized: "Model"), value: model)
            }
            self.infoRow(label: String(localized: "API version"), value: self.info.apiVersion)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
