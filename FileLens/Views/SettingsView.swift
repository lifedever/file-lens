import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("filelens.autoExpandInspector") private var autoExpandInspector: Bool = true

    var body: some View {
        Form {
            Toggle("Auto-expand inspector when selecting a file", isOn: $autoExpandInspector)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
            }
            Text("FileLens").font(.title2.bold())
            Text(verbatim: "v\(version) (\(build))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("about.tagline", comment: "App tagline")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Spacer()
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/lifedever/file-lens")!)
                Link("Issues", destination: URL(string: "https://github.com/lifedever/file-lens/issues")!)
            }
            .font(.callout)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
