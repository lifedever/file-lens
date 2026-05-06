import SwiftUI

struct InspectorView: View {
    let file: FileNode?

    var body: some View {
        if let f = file {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(f.name).font(.headline).lineLimit(2)
                    Group {
                        labeled("Kind", f.kind.capitalized)
                        labeled("Size", byteFormatter.string(fromByteCount: f.size))
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

    private func labeled(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.callout).textSelection(.enabled)
        }
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
                Text(t)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }
}
