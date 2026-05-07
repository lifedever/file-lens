import AppKit
import SwiftUI

/// 单实例守门 + Dock 反向激活时的窗口重开通道。
///
/// **单实例**:LaunchServices 在不同安装路径(DMG 安装的 /Applications +
/// dev 编译的产物)之间会把同一个 bundle ID 当成不同 App 启动,导致 Dock
/// 出两个图标。这里在 willFinishLaunching 阶段主动查 NSRunningApplication,
/// 发现重复就激活已有实例、自己退出。
///
/// **窗口重开**:用户红点关窗后再点 Dock 图标
/// (applicationShouldHandleReopen),SwiftUI WindowGroup 不会自动重建,
/// 需要 openWindow(id:) 主动唤起。FileLensApp 在 ContentView onAppear 时
/// 把 closure 注入到这里,reopen 触发时调用即可。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    /// SwiftUI 的 openWindow(id:) 回调。closure 而不是直接持 OpenWindowAction,
    /// 因为后者只能在 SwiftUI View 上下文里取。
    var openMainWindow: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 单实例守门必须在 willFinishLaunching 跑,didFinishLaunching 太晚
        // (那时 NSApp 已对外可见)。
        Self.enforceSingleInstance()
    }

    /// 如果存在另一个相同 bundleID 的进程,激活它,自己退出。
    /// 用 NSRunningApplication 而不是查 ps —— 前者由 LaunchServices 管,
    /// 是权威数据源。
    static func enforceSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { other in
                // !isTerminated 防 race:用户脚本里 pkill -9 刚发,
                // launchd 的 running list 还来不及刷新,会把已死的进程
                // 报回来。如果当真去 activate,新启动的自己也会被 exit
                // 掉,人就完全打不开 App 了。
                other.processIdentifier != me.processIdentifier && !other.isTerminated
            }
        guard let existing = others.first else { return }
        existing.activate(options: [.activateAllWindows])
        // exit 而不是 NSApp.terminate(_:) —— 后者会触发
        // applicationShouldTerminate 等钩子,绕一圈反而慢;我们要的就是
        // 当场结束。
        exit(0)
    }

    /// 用户点 Dock 图标或菜单栏图标且当前没有可见窗口时触发(标准行为)。
    /// hasVisibleWindows == false 意味着主窗口被关了,需要重开。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            openMainWindow?()
        }
        return true
    }
}
