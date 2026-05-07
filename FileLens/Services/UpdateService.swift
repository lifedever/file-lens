import AppKit
import Foundation

/// Glue between UpdateChecker and the user-facing UI. Two entry points:
///
///   - `checkAndPrompt()`: fires when the user explicitly asks (menu item,
///     About-tab button). Always shows a result — either an "Update available"
///     alert or "You're on the latest version".
///
///   - `checkInBackgroundIfNeeded()`: silent on launch, gated by a 24h
///     timer. Only surfaces UI when there's actually an update.
@MainActor
enum UpdateService {
    private static let lastCheckKey = "filelens.lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 3600

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func checkAndPrompt() {
        Task {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            let info = await UpdateChecker.shared.checkForUpdate(currentVersion: currentVersion)
            await MainActor.run {
                if let info {
                    presentUpdateAlert(info)
                } else {
                    presentUpToDateAlert()
                }
            }
        }
    }

    static func checkInBackgroundIfNeeded() {
        // 用户在 设置 → 通用 中可以关掉自动检查;关闭后这里直接退出。
        // 每次启动都跑一次 check —— 单次 HTTP 请求开销可以忽略,有更新了才弹
        // 框,没更新就静默,体验上没成本。lastCheckKey 仍写进去给未来用。
        let auto = UserDefaults.standard.object(forKey: "filelens.autoCheckUpdate")
            as? Bool ?? true
        guard auto else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        Task {
            let info = await UpdateChecker.shared.checkForUpdate(currentVersion: currentVersion)
            // Background path: only nag if there's actually something new.
            if let info {
                await MainActor.run { presentUpdateAlert(info) }
            }
        }
    }

    // MARK: - Alerts

    private static func presentUpdateAlert(_ info: UpdateInfo) {
        // 走 SwiftUI sheet —— UpdateController 准备好状态,主窗口的
        // .updateSheet() modifier 监听到 showUpdateDialog 翻转就把 dialog 弹出。
        // 不要用 NSApp.runModal(详见 UpdateController 注释)。
        UpdateController.shared.prepare(info: info, currentVersion: currentVersion)
    }

    private static func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.uptodate.title",
                                              value: "You're up to date",
                                              comment: "")
        alert.informativeText = NSLocalizedString("update.uptodate",
                                                  value: "You're on the latest version.",
                                                  comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", value: "OK", comment: ""))
        alert.runModal()
    }
}
