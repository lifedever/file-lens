import SwiftUI
import AppKit
import KeyboardShortcuts

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
            PreferencesSettingsView()
                .tabItem { Label("settings.preferences", systemImage: "slider.horizontal.3") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            SupportSettingsView()
                .tabItem { Label("settings.support", systemImage: "heart") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Preferences (索引 + 工作区默认)

private struct PreferencesSettingsView: View {
    @AppStorage("filelens.autoExpandInspector") private var autoExpandInspector: Bool = false
    @AppStorage("filelens.ignoreHidden") private var ignoreHidden: Bool = true
    @AppStorage("filelens.ignoreFolders") private var ignoreFolders: String =
        ".git, node_modules, .build, Pods, DerivedData, .next, .cache"
    @AppStorage("filelens.newArrivalsDays") private var newArrivalsDays: Int = 7
    @AppStorage("filelens.staleDays") private var staleDays: Int = 30

    var body: some View {
        Form {
            // 行为
            Section {
                Toggle("Auto-expand inspector when selecting a file", isOn: $autoExpandInspector)
            }

            // 索引(隐藏文件开关)
            Section {
                Toggle("settings.ignoreHidden", isOn: $ignoreHidden)
            } header: {
                Text("settings.section.indexing")
            }

            // 排除规则:用 TextEditor 而不是 TextField。Form.grouped 对带
            // `axis: .vertical` 的 TextField 一律做 LabeledContent,labelsHidden /
            // 空 title + prompt 都救不回来,placeholder 仍会被当成左侧 label 渲染。
            // TextEditor 不走 Form 的 TextField 特化路径,默认就是全宽内容。
            Section {
                TextEditor(text: $ignoreFolders)
                    .font(.callout.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 84, maxHeight: 140)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                    )
            } header: {
                Text("settings.exclude.label")
                    .textCase(nil)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
            } footer: {
                Text("settings.exclude.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 新建文件夹默认值。数字栏既支持 Stepper,也支持手动键入;
            // .controlSize(.small) 让 Stepper 上下箭头不再喧宾夺主。
            Section {
                LabeledContent("settings.newArrivalsDays.label") {
                    daysField(value: $newArrivalsDays, range: 1...90)
                }
                LabeledContent("settings.staleDays.label") {
                    daysField(value: $staleDays, range: 7...365)
                }
                Text("settings.thresholds.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("settings.section.workspaceDefaults")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// "数字输入框 + 上下箭头 + 单位" 的复合输入。TextField 拿主导地位,
    /// Stepper 只做微调;onChange 把超出区间的手动输入夹回合法范围。
    @ViewBuilder
    private func daysField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .onSubmit {
                    value.wrappedValue = min(max(value.wrappedValue, range.lowerBound),
                                             range.upperBound)
                }
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.small)
            Text("settings.days.unit")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(for: .openWindow) {
                Text("shortcut.openWindow.label")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("filelens.appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage("filelens.language") private var languageRaw: String = LanguagePreference.system.rawValue
    @AppStorage("filelens.autoCheckUpdate") private var autoCheckUpdate: Bool = true
    @State private var showingLanguageRestartAlert = false

    var body: some View {
        Form {
            // 外观和语言
            Section {
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
            }

            // 自动检查更新留在通用,自动展开 inspector / 菜单栏模式 都挪去偏好
            Section {
                Toggle("settings.autoCheckUpdate", isOn: $autoCheckUpdate)
            }

            // 配置导入导出
            Section {
                HStack {
                    Button("settings.exportConfig") {
                        do {
                            if let url = try ConfigIO.exportConfigToFile(container: modelContext.container) {
                                ToastCenter.shared.success(String(format:
                                    NSLocalizedString("config.exported.format",
                                        value: "Exported to %@",
                                        comment: ""), url.lastPathComponent))
                            }
                        } catch {
                            NSAlert(error: error).runModal()
                        }
                    }
                    .pointingHandCursor()
                    Button("settings.importConfig") {
                        do {
                            if let cfg = try ConfigIO.importConfigFromFile() {
                                let n = try ConfigIO.applyImport(cfg, container: modelContext.container)
                                if n > 0 {
                                    ToastCenter.shared.success(String(format:
                                        NSLocalizedString("settings.importConfig.result.format",
                                            value: "Imported %d new folder(s)",
                                            comment: ""), n))
                                } else {
                                    ToastCenter.shared.info(
                                        NSLocalizedString("config.imported.none",
                                            value: "Nothing to import (folders already exist)",
                                            comment: ""))
                                }
                            }
                        } catch {
                            NSAlert(error: error).runModal()
                        }
                    }
                    .pointingHandCursor()
                    Spacer()
                }
            } header: {
                Text("settings.section.config")
            }

            // 欢迎页
            Section {
                HStack {
                    Text("welcome.replay.label")
                    Spacer()
                    Button("welcome.replay.button") {
                        NotificationCenter.default.post(name: .showWelcome, object: nil)
                    }
                    .pointingHandCursor()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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

// MARK: - Support

private struct SupportSettingsView: View {
    private static let websiteURL  = URL(string: "https://www.lifedever.com")!
    private static let starURL     = URL(string: "https://github.com/lifedever/file-lens")!
    private static let feedbackURL = URL(string: "https://github.com/lifedever/file-lens/issues")!

    var body: some View {
        VStack(spacing: 14) {
            // Hero card
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.pink)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle().fill(Color.pink.opacity(0.14))
                    )
                Text("support.title")
                    .font(.title3.bold())
                Text("support.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )

            // Action list
            VStack(spacing: 0) {
                supportRow(icon: "cup.and.saucer.fill",
                           title: "support.coffee",
                           url: Self.websiteURL)
                Divider().padding(.leading, 44)
                supportRow(icon: "star.fill",
                           title: "support.star",
                           url: Self.starURL)
                Divider().padding(.leading, 44)
                supportRow(icon: "bubble.left.fill",
                           title: "support.feedback",
                           url: Self.feedbackURL)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 0.5)
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func supportRow(icon: String,
                            title: LocalizedStringKey,
                            url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(title)
                    .foregroundStyle(.tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// MARK: - About

private struct AboutSettingsView: View {
    @State private var checking = false
    @State private var updateInfo: UpdateInfo?
    @State private var checkResultMessage: String?

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

            // Check for updates row
            HStack(spacing: 8) {
                Button {
                    Task { await checkUpdate() }
                } label: {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check for Updates")
                    }
                }
                .disabled(checking)
                .pointingHandCursor()
                if let msg = checkResultMessage {
                    Text(verbatim: msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
            .alert("update.available.title", isPresented: Binding(
                get: { updateInfo != nil },
                set: { if !$0 { updateInfo = nil } }
            ), presenting: updateInfo) { info in
                Button("update.download") {
                    if let url = URL(string: info.releaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                    updateInfo = nil
                }
                Button("Cancel", role: .cancel) { updateInfo = nil }
            } message: { info in
                Text(verbatim: String(format:
                    NSLocalizedString("update.available.message.format",
                        value: "A new version %@ is available.",
                        comment: ""), info.latestTag))
            }

            // Only Check Updates (above) + Website here. Sponsor / GitHub /
            // Feedback all live on the dedicated Support tab now.
            Link(destination: URL(string: "https://www.lifedever.com")!) {
                Label("about.website", systemImage: "globe")
            }
            .font(.callout)
            .padding(.top, 6)
            .pointingHandCursor()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func checkUpdate() async {
        checking = true
        checkResultMessage = nil
        defer { checking = false }
        let info = await UpdateChecker.shared.checkForUpdate(currentVersion: version)
        if let info {
            updateInfo = info
        } else {
            checkResultMessage = NSLocalizedString("update.uptodate",
                value: "You're on the latest version.", comment: "")
        }
    }
}
