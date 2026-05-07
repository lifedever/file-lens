import SwiftUI
import SwiftData

@main
struct FileLensApp: App {
    let container: ModelContainer
    /// 装单实例守门 + 主窗口重开通道。Adaptor 必须挂在 @main App 上,
    /// 否则 NSApplication 不会读到这个 delegate。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        do {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.FileLens"
            let storeURL = try StoreMigration.resolveStoreURL(bundleID: bundleID)
            let schema = Schema([Workspace.self, Rule.self, Condition.self, FileNode.self, FileTag.self])
            let config = ModelConfiguration(schema: schema, url: storeURL)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to init ModelContainer: \(error)")
        }
        // Note: do NOT call NSApp.* here — NSApplication is not yet initialized
        // at SwiftUI App.init() time. Apply appearance from .onAppear below.
    }

    var body: some Scene {
        // 给 WindowGroup 显式 id —— openWindow(id:"main") 在 Dock 反向激活
        // 时(applicationShouldHandleReopen)会用到,把窗口从背景拉回来。
        WindowGroup(id: "main") {
            ContentView()
                .onAppear {
                    applyPersistedAppearance()
                    GlobalShortcuts.register()
                    // Migrate older installs: rules created before
                    // BuiltInRules.all() localized at creation time are
                    // stored with English keys and read awkwardly in the
                    // editor. This rewrites them once.
                    RuleNameMigration.runIfNeeded(container: container)
                    WorkspaceSortOrderMigration.runIfNeeded(container: container)
                    WorkspaceRecursiveMigration.runIfNeeded(container: container)
                    ArchivesISOMigration.runIfNeeded(container: container)
                    // Silent update probe — only nags if there's a newer
                    // release and we haven't checked in the last 24h.
                    UpdateService.checkInBackgroundIfNeeded()
                }
                .modifier(MainWindowProxyInstaller())
        }
        .modelContainer(container)
        .commands { FileLensCommands() }

        Settings {
            SettingsView()
        }
        .modelContainer(container)
    }

    private func applyPersistedAppearance() {
        let raw = UserDefaults.standard.string(forKey: "filelens.appearance") ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}

/// 把 SwiftUI 的 openWindow action 注册给 AppDelegate(用于
/// applicationShouldHandleReopen —— 用户点 Dock 图标时如果没有可见窗口,
/// 重新唤起一个),并设置主窗口的 frame autosave。
private struct MainWindowProxyInstaller: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDelegate.shared.openMainWindow = {
                    openWindow(id: "main")
                }
                // 延迟一帧:onAppear 时 NSWindow 可能还在 SwiftUI 的 mount
                // 阶段,立刻取 NSApp.windows 偶尔取不到本窗口。
                DispatchQueue.main.async {
                    configureMainWindow()
                }
            }
    }

    private func configureMainWindow() {
        let main = NSApp.windows.first { window in
            guard !(window is NSPanel), window.canBecomeMain else { return false }
            let id = window.identifier?.rawValue.lowercased() ?? ""
            return !id.contains("settings") && !id.contains("preference")
        }
        guard let main else { return }
        // 持久化窗口尺寸 + 位置。setFrameAutosaveName 自带 saveFrame,
        // 但 *恢复* 只在 nib-loaded 窗口时生效 —— SwiftUI 程序化创建的窗口
        // 必须显式 setFrameUsingName 拉一次,否则会按默认尺寸渲染。
        let name = "FileLens.MainWindow"
        main.setFrameAutosaveName(name)
        main.setFrameUsingName(name)
    }
}
