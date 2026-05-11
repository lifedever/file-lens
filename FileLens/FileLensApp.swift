import SwiftUI
import SwiftData

/// 检测当前进程是不是被 XCTest 主控启动 —— 走 test host 跑 unit test 时
/// `XCTestConfigurationFilePath` 必有(Apple 用来定位 test bundle)。
/// 测试模式必须**避免任何 prod 副作用**:不读 prod data dir、不写 prod
/// UserDefaults、不发更新检查请求。否则一跑测试就污染用户的实际数据。
private let isRunningTests: Bool =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

@main
struct FileLensApp: App {
    let storeManager: WorkspaceStoreManager
    var container: ModelContainer { storeManager.catalog }
    /// 装单实例守门 + 主窗口重开通道。Adaptor 必须挂在 @main App 上,
    /// 否则 NSApplication 不会读到这个 delegate。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        do {
            self.storeManager = try WorkspaceStoreManager()
        } catch {
            fatalError("Failed to init WorkspaceStoreManager: \(error)")
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
                    // 测试模式:跳过所有 prod 副作用(主题恢复、热键注册、迁移、
                    // 更新检查)—— 避免污染 prod UserDefaults / 发网络请求。
                    guard !isRunningTests else { return }
                    applyPersistedAppearance()
                    GlobalShortcuts.register()
                    // ⚠️ 必须**最先**跑 —— 把老版本 default.store 里的
                    // workspace/rule/condition 迁到新的 catalog.sqlite。
                    // 后面所有 migration 都假设数据在 catalog,迁完才能命中。
                    StoreMigrationV2.runIfNeeded(
                        baseDir: storeManager.baseDir,
                        catalog: storeManager.catalog
                    )
                    // Migrate older installs: rules created before
                    // BuiltInRules.all() localized at creation time are
                    // stored with English keys and read awkwardly in the
                    // editor. This rewrites them once.
                    RuleNameMigration.runIfNeeded(container: container)
                    WorkspaceSortOrderMigration.runIfNeeded(container: container)
                    WorkspaceRecursiveMigration.runIfNeeded(container: container)
                    WorkspaceViewSettingsMigration.runIfNeeded(context: ModelContext(container))
                    ArchivesISOMigration.runIfNeeded(container: container)
                    // 上次会话强退留下的"卡在索引中"状态 + 未完成 deletion 清理
                    WorkspaceStateRecovery.runIfNeeded(storeManager: storeManager)
                    // Silent update probe — only nags if there's a newer
                    // release and we haven't checked in the last 24h.
                    UpdateService.checkInBackgroundIfNeeded()
                }
                .modifier(MainWindowProxyInstaller())
                .updateSheet()
                .environment(\.workspaceStoreManager, storeManager)
        }
        .modelContainer(container)
        .commands { FileLensCommands() }

        Settings {
            SettingsView()
                .environment(\.workspaceStoreManager, storeManager)
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
                // 测试模式不挂 frameAutosave,不污染 prod UserDefaults
                guard !isRunningTests else { return }
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
