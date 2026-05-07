import SwiftUI
import SwiftData
import AppKit

/// 把 FileNode 抽成 plain 值的视图模型 —— 父视图(ContentView body)在动画
/// *开始之前* 就把 SwiftData lazy fault(`f.tags`、relation 关系等)和 icon
/// 同步 IO 都解算完,InspectorView body 拿到的全是 primitives,不会触发任何
/// 异步加载或 fault。
///
/// 老实现的 bug:
///   - InspectorView 内 `.task(id: f.id)` 异步加载 icon。task 在 body 第一次
///     渲染 *之后* 才跑,落在 AppKit 的 slide 动画进行中;FileIconCache 第一次
///     命中冷扩展名时同步 IO 会阻 main thread,动画就卡在中间。
///   - 同时 `f.tags.map(\.name)` 在 InspectorView body 里访问 SwiftData
///     relationship,如果 tags 没被 fault 过(Table 没渲染过该 row),也会
///     在 inspector 出现时同步 IO 一次。
struct InspectorSnapshot {
    /// 标签信息:名字 + 对应规则的颜色(hex)。颜色让 Inspector 的标签跟
    /// sidebar 一样带圆点视觉。tag 找不到对应 rule 时(比如 manual tag、
    /// 或 rule 已被删但 tag 还在)给一个中性灰兜底。
    struct TagInfo: Hashable {
        let name: String
        let colorHex: String
    }

    let id: UUID
    let name: String
    let size: Int64
    let kind: String
    let dateAdded: Date
    let dateModified: Date
    let relativePath: String
    let tags: [TagInfo]
    let icon: NSImage
    /// 解算一次的真实 file URL,给 PreviewHost 用。父 body 里同步取出,
    /// 让 InspectorView 的预览子树拿到 primitive,避免动画期间触发 bookmark
    /// resolve(那是 IO)。失败为 nil → PreviewHost 显示 unsupported 兜底。
    let url: URL?

    @MainActor
    init(file f: FileNode, rules: [Rule]) {
        self.id = f.id
        self.name = f.name
        self.size = f.size
        self.kind = f.kind
        self.dateAdded = f.dateAdded
        self.dateModified = f.dateModified
        self.relativePath = f.relativePath
        self.icon = FileIconCache.icon(for: f)
        self.url = FileActions.url(for: f)

        // 从 workspace 的 rule 列表里建一个 name → color 索引,FileTag 拿
        // 它名字反查颜色。
        let colorByName: [String: String] = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.name, $0.color) }
        )
        self.tags = f.tags.map { tag in
            TagInfo(name: tag.name, colorHex: colorByName[tag.name] ?? "#9CA3AF")
        }
    }
}

struct InspectorView: View {
    let snapshot: InspectorSnapshot?
    /// 实际选中的文件,作为 actions 的目标。空数组时不显示操作面板。
    /// 跟 snapshot 解耦:snapshot 只是单文件的展示数据,actions 走 array
    /// 既支持单选也支持多选(rename 之类内部判断 count == 1 自动隐藏)。
    let selectedFiles: [FileNode]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if !selectedFiles.isEmpty {
            content
        } else {
            Text("No selection").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        // Actions 用 ScrollView 包,文件选项一多/inspector 不够高时也能滚。
        // metadata 区域不滚,跟着 inspector 自然撑(顶部固定到滑入位置)。
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if selectedFiles.count > 1 {
                    multiSelectHeader
                } else if let s = snapshot, let file = selectedFiles.first {
                    // 顶部预览区:单选时显示。多选时不构造,与原有 multiSelect
                    // 路径完全一致,避免给「批量选中」场景额外造视觉噪声。
                    PreviewHost(file: file, url: s.url)
                    singleHeader(for: s)
                    Divider()
                    metadata(for: s)
                    Divider()
                    tagsSection(for: s)
                }

                Divider()
                actionsSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header variants

    /// 单选 header:只显示文件名 + 大小。图标已经在上方 PreviewHost 里以
    /// 大尺寸出现(图片是缩略图、unsupported 是 96pt 扩展名图标),这里
    /// 再重复 56pt 小图标就是噪音。
    private func singleHeader(for s: InspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: s.name)
                .font(.headline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(verbatim: Self.bytes.string(fromByteCount: s.size))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 多选时的头部:用文件夹/集合图标 + "N 项已选" + 总大小。比硬塞首文件
    /// 的 metadata 更诚实 —— 多文件时每个的 kind / date / tags 不一定相同。
    private var multiSelectHeader: some View {
        let totalSize = selectedFiles.reduce(Int64(0)) { $0 + $1.size }
        let count = selectedFiles.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .padding(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(format:
                    NSLocalizedString("inspector.multiselect.format",
                        value: "%lld items selected", comment: ""), Int64(count)))
                    .font(.headline)
                Text(verbatim: Self.bytes.string(fromByteCount: totalSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Metadata / tags

    private func metadata(for s: InspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Kind",     KindDisplay.localizedName(s.kind))
            labeled("Added",    Self.dateString(s.dateAdded))
            labeled("Modified", Self.dateString(s.dateModified))
            labeled("Location", s.relativePath)
        }
    }

    @ViewBuilder
    private func tagsSection(for s: InspectorSnapshot) -> some View {
        Text("Tags").font(.caption).foregroundStyle(.secondary)
        if s.tags.isEmpty {
            Text("No tags").foregroundStyle(.tertiary).font(.caption)
        } else {
            FlowTags(tags: s.tags)
        }
    }

    // MARK: - Actions

    /// 把 FileActionRegistry 渲染成 inspector 风格的纵向按钮组,跟右键菜单
    /// 共用同一份 action 定义。组之间细分割线,destructive 用 .red 色。
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("inspector.section.actions")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(FileActionGroup.allCases.enumerated()), id: \.offset) { idx, group in
                    ForEach(group.kinds) { kind in
                        if kind.isAvailable(for: selectedFiles) {
                            InspectorActionButton(kind: kind,
                                                  files: selectedFiles,
                                                  modelContext: modelContext)
                        }
                    }
                    if idx < FileActionGroup.allCases.count - 1 {
                        Divider().padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func labeled(_ key: LocalizedStringKey, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: v).font(.callout).textSelection(.enabled)
        }
    }

    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// 复用一个 DateFormatter 实例。Date.formatted(date:time:) 每次构造
    /// FormatStyle,SwiftUI body 重建时累积成本会被 inspector reflow 放大。
    private static let dateF: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    private static func dateString(_ d: Date) -> String { dateF.string(from: d) }
}

/// Inspector 操作面板里每一行按钮:左侧 SF Symbol + label,hover 时 row
/// 整体淡灰背景。borderless 样式贴合 macOS 系统设置的视觉。
private struct InspectorActionButton: View {
    let kind: FileActionKind
    let files: [FileNode]
    let modelContext: ModelContext

    @State private var isHovering = false

    var body: some View {
        Button {
            kind.perform(files, modelContext: modelContext)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(kind.role == .destructive ? Color.red : .primary)
                Text(kind.titleKey)
                    .font(.callout)
                    .foregroundStyle(kind.role == .destructive ? Color.red : .primary)
                Spacer(minLength: 4)
                if let hint = kind.shortcutHint {
                    // 不用 monospaced —— 系统右键菜单用普通 SF 字体,符号 +
                    // 字母混排时密度更协调。.secondary 比 .tertiary 更可读。
                    Text(verbatim: hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.secondary.opacity(0.14) : .clear)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}

private struct FlowTags: View {
    let tags: [InspectorSnapshot.TagInfo]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hexString: tag.colorHex))
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                        )
                        .frame(width: 8, height: 8)
                    Text(verbatim: TagDisplay.localizedName(tag.name))
                        .font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10), in: Capsule())
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
