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
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard now - last > checkInterval else { return }
        UserDefaults.standard.set(now, forKey: lastCheckKey)

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
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.available.title",
                                              value: "Update Available",
                                              comment: "")
        alert.informativeText = String(format:
            NSLocalizedString("update.available.message.format",
                              value: "A new version %@ is available.",
                              comment: ""), info.latestTag)
        alert.addButton(withTitle: NSLocalizedString("update.download",
                                                     value: "Download",
                                                     comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel",
                                                     value: "Cancel",
                                                     comment: ""))
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: info.releaseURL) {
            NSWorkspace.shared.open(url)
        }
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
