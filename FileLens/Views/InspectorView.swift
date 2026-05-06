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
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { t in
                Text(verbatim: TagDisplay.localizedName(t))
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// True wrapping HStack for tag chips. Each chip takes only the width it needs;
/// chips wrap to the next line when the row overflows.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
