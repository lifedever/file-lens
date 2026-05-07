import SwiftUI
import AppKit

/// Inspector 顶部预览区按文件 kind 派发出的子视图分类。
/// 加新分类时:在 PreviewHost.kind(for:) 里映射,然后在 PreviewHost.body
/// switch 里 wire 一个新的子视图。外围(InspectorView)零改动。
enum PreviewKind {
    /// NSImage 全分辨率渲染。仅 image kind 走这条 —— 直接读字节比 QL 还快。
    case image
    /// 走 ThumbnailService large 档(512pt @2x)。movie/document/text/code 用。
    case quickLook
    /// v2 留位:文本 / 代码首屏纯文本预览。当前 fallback 到 unsupported 渲染。
    case text
    /// 大号扩展名图标 + "No preview" 文案。audio/archive/other 用。
    case unsupported
}

/// Inspector 顶部预览容器。宽度撑满 inspector pane,高度按内容自适应,
/// 上限 320pt(避免竖屏照片把 inspector 撑得过高,把下方 metadata 顶出
/// 视区)。多选时调用方不构造它,所以这里默认假设单文件。
struct PreviewHost: View {
    let file: FileNode
    let url: URL?

    /// 按 FileNode.kind 决定走哪条预览路径。kind 取值见 KindClassifier。
    static func kind(for file: FileNode) -> PreviewKind {
        if file.isDirectory { return .unsupported }
        switch file.kind {
        case "image":                                  return .image
        case "movie", "document", "text", "code":      return .quickLook
        // PDF / RTF / MD 由 KindClassifier 归到 "document"
        // text / code 类 QL 也能渲染成「首页文本」首屏
        // archive / audio / other 不参与缩略图升级
        default:                                       return .unsupported
        }
    }

    var body: some View {
        Group {
            switch Self.kind(for: file) {
            case .image:        ImagePreview(file: file, url: url)
            case .quickLook:    QuickLookPreview(file: file, url: url)
            case .text:         UnsupportedPreview(file: file)   // v2 留位
            case .unsupported:  UnsupportedPreview(file: file)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
