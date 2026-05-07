import SwiftUI
import AppKit

/// 不支持预览的兜底视图。大号扩展名图标 + "No preview" 文案。
/// 也用作 .text v2 case 的当前 fallback —— text 实现接进来后会替换掉。
struct UnsupportedPreview: View {
    let file: FileNode

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: FileIconCache.icon(for: file))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("preview.unsupported")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
