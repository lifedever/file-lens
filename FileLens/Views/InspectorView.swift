import SwiftUI
import AppKit

struct InspectorView: View {
    let file: FileNode?

    var body: some View {
        if let f = file {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: systemIcon(for: f))
                            .resizable().interpolation(.high)
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name)
                                .font(.headline)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Text(byteFormatter.string(fromByteCount: f.size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Divider()

                    Group {
                        labeled("Kind", KindDisplay.localizedName(f.kind))
                        labeled("Added", f.dateAdded.formatted(date: .abbreviated, time: .shortened))
                        labeled("Modified", f.dateModified.formatted(date: .abbreviated, time: .shortened))
                        labeled("Path", f.relativePath)
                    }

                    Divider()

                    Text("Tags").font(.caption).foregroundStyle(.secondary)
                    if f.tags.isEmpty {
                        Text("No tags").foregroundStyle(.tertiary).font(.caption)
                    } else {
                        FlowTags(tags: f.tags.map(\.name))
                    }
                }
                .padding()
            }
        } else {
            Text("No selection").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func labeled(_ key: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.callout).textSelection(.enabled)
        }
    }

    private func systemIcon(for f: FileNode) -> NSImage {
        if let url = FileActions.url(for: f) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }
}

private struct FlowTags: View {
    let tags: [String]
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 60, maximum: 160), spacing: 4)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.self) { t in
                Text(verbatim: TagDisplay.localizedName(t))
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }
}
