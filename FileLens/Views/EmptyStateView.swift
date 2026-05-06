import SwiftUI

struct EmptyStateView: View {
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Add a folder to get started")
                .font(.title2)
            Text("FileLens watches folders you choose and groups files by tags.\nFiles never move from their original location.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add Folder…", action: onAddFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
