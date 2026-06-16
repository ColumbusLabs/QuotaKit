import SwiftUI

struct ReleaseNotesView: View {
    private let versions = MobileReleaseNotesCatalog.versions

    private var latestVersion: ReleaseNotesVersion? {
        self.versions.first
    }

    private var historicalVersions: ArraySlice<ReleaseNotesVersion> {
        self.versions.dropFirst()
    }

    var body: some View {
        List {
            if let latestVersion = self.latestVersion {
                Section("Latest") {
                    ReleaseNotesCard(version: latestVersion)
                }
            }

            Section("History") {
                if self.historicalVersions.isEmpty {
                    Text("Older iOS release notes will appear here as new versions ship.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(self.historicalVersions)) { version in
                        DisclosureGroup {
                            ReleaseNotesContent(version: version)
                                .padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                    Text("\(String(localized: "Version")) \(version.version)")
                                        .fontWeight(.semibold)
                                    ReleaseNotesBadge(title: version.status)
                                }

                                Text(version.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Release Notes")
    }
}

struct ReleaseNotesCard: View {
    let version: ReleaseNotesVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(localized: "Version")) \(self.version.version)")
                        .font(.headline)
                    Text(self.version.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ReleaseNotesBadge(title: self.version.status)
            }

            ReleaseNotesContent(version: self.version)
        }
        .padding(.vertical, 8)
    }
}

struct ReleaseNotesContent: View {
    let version: ReleaseNotesVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(self.version.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 7)

                                // Use LocalizedStringKey init so markdown
                                // (specifically `[label](url)` links) renders
                                // as tappable, with bold / italic also
                                // honored. Existing items without markdown
                                // syntax continue to render as plain text.
                                Text(.init(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .tint(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ReleaseNotesBadge: View {
    let title: String

    var body: some View {
        Text(self.title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}
