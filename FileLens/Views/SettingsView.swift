import SwiftUI
import AppKit

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "appearance.system"
        case .light:  return "appearance.light"
        case .dark:   return "appearance.dark"
        }
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum LanguagePreference: String, CaseIterable, Identifiable {
    case system = "system"
    case en = "en"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "language.system"
        case .en:     return "language.en"
        case .zhHans: return "language.zhHans"
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 460)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("filelens.appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage("filelens.language") private var languageRaw: String = LanguagePreference.system.rawValue
    @AppStorage("filelens.autoExpandInspector") private var autoExpandInspector: Bool = true

    @State private var showingLanguageRestartAlert = false

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppearancePreference.allCases) { p in
                    Text(p.titleKey).tag(p.rawValue)
                }
            }
            .onChange(of: appearanceRaw) { _, new in
                (AppearancePreference(rawValue: new) ?? .system).apply()
            }

            Picker("Language", selection: $languageRaw) {
                ForEach(LanguagePreference.allCases) { p in
                    Text(p.titleKey).tag(p.rawValue)
                }
            }
            .onChange(of: languageRaw) { _, new in
                if new == LanguagePreference.system.rawValue {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([new], forKey: "AppleLanguages")
                }
                showingLanguageRestartAlert = true
            }

            Toggle("Auto-expand inspector when selecting a file", isOn: $autoExpandInspector)
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .fixedSize(horizontal: false, vertical: true)
        .alert("language.restart.title", isPresented: $showingLanguageRestartAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restart Now") { restartApp() }
        } message: {
            Text("language.restart.message")
        }
    }

    private func restartApp() {
        guard let url = Bundle.main.bundleURL as URL? else { return }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApp.terminate(nil)
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
            } else {
                Image(systemName: "app.fill")
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.tint)
            }
            Text("FileLens").font(.title2.bold())
            Text(verbatim: "v\(version) (\(build))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("about.tagline")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/lifedever/file-lens")!)
                Link("Issues", destination: URL(string: "https://github.com/lifedever/file-lens/issues")!)
            }
            .font(.callout)
            .padding(.top, 6)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}
