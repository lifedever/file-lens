import AppKit
import Foundation
import SwiftData

/// 更新对话框背后的状态机:available → downloading → complete → installing。
/// 下载 / 验证 DMG / 替换 .app + 重启 都在这里完成,UI(UpdateDialogView)
/// 只观察发布的 Published 状态做渲染。
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    // 静态 release 信息(进入对话框时由 UpdateService 注入)
    @Published var latestTag: String = ""
    @Published var currentVersion: String = ""
    @Published var releaseNotes: String = ""
    /// DMG 下载源优先级列表。startDownload 从 [0] 开始,失败时自动切下一个。
    /// 通常 manifest 给:[Gitee, GitHub] —— 国内网络下 Gitee 快,出问题
    /// 自动用 GitHub。
    @Published var downloadURLs: [URL] = []
    private var currentURLIndex: Int = 0
    /// 浏览器去打开的 Release 页面 —— 所有镜像下载都失败时,引导用户手动
    /// 去这个页面下载。
    @Published var releaseURL: URL?

    /// 控制更新对话框的显示。Dialog 通过主窗口的 `.sheet(isPresented:)`
    /// 挂载,**不能用 NSApp.runModal**:modal session 会把 run loop 切到
    /// `NSModalPanelRunLoopMode`,SwiftUI 在该 mode 下对 `ProgressView(value:)`
    /// 的 view diff 不重算 value 参数,导致进度条永远停在小值;同时从后台
    /// OperationQueue 调度过来的 `Task { @MainActor }` / `DispatchQueue.main.async`
    /// 也不会被稳定 pump,onComplete 状态切换偶尔丢失。
    /// 改用 SwiftUI 的 `.sheet`(底层走 NSPanel + 普通 run loop),所有
    /// @Published 状态更新都正常生效。参考 TaskTick(Sources/Engine/UpdateChecker.swift)。
    @Published var showUpdateDialog = false

    // 下载状态
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var downloadComplete = false
    @Published var downloadedFileURL: URL?

    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: DownloadDelegate?

    /// Stalled detector:每次收到进度都 reset 一次。N 秒没动静 → 认为这个 URL
    /// 卡死,主动 cancel,触发 onError 走到下一个镜像。比单纯靠 URLSession
    /// 的 `timeoutIntervalForRequest` 早响应,用户不用干等到 OS 超时才换源。
    private var stallTimer: Timer?
    private let stallTimeout: TimeInterval = 30

    private init() {}

    /// 注入 release 信息并 reset 下载状态;**最后一步**把 showUpdateDialog
    /// 翻成 true,主窗口的 `.sheet(isPresented:)` 监听到就把 dialog 弹出来。
    func prepare(info: UpdateInfo, currentVersion: String) {
        self.latestTag = info.latestTag
        self.currentVersion = currentVersion
        self.releaseNotes = info.body ?? ""
        self.downloadURLs = info.downloadURLs.isEmpty
            ? fallbackURLs(tag: info.latestTag)
            : info.downloadURLs
        self.releaseURL = URL(string: info.releaseURL)
        self.currentURLIndex = 0
        // reset
        isDownloading = false
        downloadProgress = 0
        downloadedBytes = 0
        totalBytes = 0
        downloadComplete = false
        downloadedFileURL = nil
        // 触发 sheet 弹出
        showUpdateDialog = true
    }

    /// manifest / API 都没给 DMG URL 时的兜底 —— 按约定文件名拼 GitHub
    /// release 直链。
    private func fallbackURLs(tag: String) -> [URL] {
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let dmgName = "FileLens-\(version)-universal.dmg"
        return [URL(string:
            "https://github.com/lifedever/file-lens/releases/download/v\(version)/\(dmgName)")]
            .compactMap { $0 }
    }

    // MARK: - Download

    func startDownload() {
        guard !downloadURLs.isEmpty else { return }
        NSLog("[FileLens-update] download URL list (priority order):")
        for (idx, u) in downloadURLs.enumerated() {
            NSLog("[FileLens-update]   [%d] %@", idx, u.absoluteString)
        }
        currentURLIndex = 0
        isDownloading = true
        downloadProgress = 0
        downloadedBytes = 0
        downloadComplete = false
        beginDownload(url: downloadURLs[currentURLIndex])
    }

    /// 真正发起一次下载请求。如果当前 URL 失败,onError 里会切到下一个 URL
    /// 重新调本函数,直到所有 URL 都试过才向用户报错。
    private func beginDownload(url: URL) {
        let delegate = DownloadDelegate { [weak self] progress, received, total in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.downloadedBytes = received
                self?.totalBytes = total
                self?.resetStallTimer()
            }
        } onComplete: { [weak self] fileURL in
            Task { @MainActor in
                self?.cancelStallTimer()
                self?.downloadProgress = 1.0
                self?.downloadComplete = true
                self?.downloadedFileURL = fileURL
                self?.isDownloading = false
            }
        } onError: { [weak self] message in
            Task { @MainActor in
                guard let self = self else { return }
                self.cancelStallTimer()
                // 当前 URL 失败 → 切下一个继续。一组 URL 全部失败才弹错误。
                self.currentURLIndex += 1
                if self.currentURLIndex < self.downloadURLs.count {
                    self.downloadProgress = 0
                    self.downloadedBytes = 0
                    self.beginDownload(url: self.downloadURLs[self.currentURLIndex])
                } else {
                    self.isDownloading = false
                    self.downloadComplete = false
                    self.downloadProgress = 0
                    self.showDownloadError(message)
                }
            }
        }
        self.downloadDelegate = delegate
        NSLog("[FileLens-update] starting download: %@", url.absoluteString)
        // 走代理 / 慢网络默认 60s 偏紧,但也不能无限大,否则单个挂死的 URL
        // 会拖住整个 fallback 链路。120s 单请求 + 30 分钟总上限 + 应用层
        // stalled detector(30s 无进度自动切下个 URL)三层兜底。
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
        resetStallTimer()
    }

    // MARK: - Stalled detector

    private func resetStallTimer() {
        stallTimer?.invalidate()
        stallTimer = Timer.scheduledTimer(withTimeInterval: stallTimeout,
                                          repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleStalledDownload()
            }
        }
    }

    private func cancelStallTimer() {
        stallTimer?.invalidate()
        stallTimer = nil
    }

    private func handleStalledDownload() {
        guard isDownloading, !downloadComplete else { return }
        NSLog("[FileLens-update] download stalled (no progress for %ds), failing over to next URL",
              Int(stallTimeout))
        // cancel 会走 didCompleteWithError → onError → 自动切下一个 URL
        downloadTask?.cancel()
    }

    func cancelDownload() {
        cancelStallTimer()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
        downloadComplete = false
    }

    // MARK: - Install + Restart

    func installAndRestart() {
        guard let fileURL = downloadedFileURL else { return }
        let dmgPath = fileURL.path

        // dev 构建(.dev bundle ID)不做自替换 —— 防止把 dev 装成 prod 后
        // 路径混乱。直接打开 DMG 让用户手动拖装。
        let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
        if isDev {
            NSWorkspace.shared.open(fileURL)
            return
        }

        // 先在不退出 app 的前提下挂载验证 DMG,如果 DMG 损坏 / 空,就别白瞎
        // quit 应用了。
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        verify.arguments = ["attach", dmgPath, "-nobrowse", "-noverify"]
        let pipe = Pipe()
        verify.standardOutput = pipe
        verify.standardError = FileHandle.nullDevice
        do {
            try verify.run()
            verify.waitUntilExit()
        } catch {
            showDMGError()
            return
        }
        guard verify.terminationStatus == 0 else {
            showDMGError()
            return
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        guard let mountLine = output.components(separatedBy: "\n")
                .first(where: { $0.contains("/Volumes/") }),
              let volumeRange = mountLine.range(of: "/Volumes/") else {
            showDMGError()
            return
        }
        let mountPoint = String(mountLine[volumeRange.lowerBound...])
            .trimmingCharacters(in: .whitespaces)
        let sourceApp = "\(mountPoint)/FileLens.app"

        guard FileManager.default.fileExists(atPath: sourceApp) else {
            detachQuietly(mountPoint)
            showDMGError()
            return
        }

        let destApp = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        // 装重启脚本:等当前 app 退出 → rm + cp 替换 → detach DMG → open 新 app
        let script = """
        #!/bin/bash
        MOUNT_POINT="\(mountPoint)"
        SOURCE_APP="\(sourceApp)"
        DEST_APP="\(destApp)"
        APP_PID=\(pid)

        for i in $(seq 1 60); do
            if ! kill -0 "$APP_PID" 2>/dev/null; then break; fi
            sleep 0.5
        done

        rm -rf "$DEST_APP"
        cp -R "$SOURCE_APP" "$DEST_APP"
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null
        open "$DEST_APP"
        rm -f "$0"
        """
        let scriptPath = NSTemporaryDirectory() + "filelens_update.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath]
            try proc.run()
        } catch {
            detachQuietly(mountPoint)
            NSWorkspace.shared.open(fileURL)
            return
        }

        // 退出前把 SwiftData mainContext 落盘,避免新版本启动看不到刚才的改动。
        // 失败不阻塞 —— 安装已经在后台脚本里跑了,这里 best-effort。
        if let container = NSApp.keyWindow?.contentViewController?
            .view.window?.windowController as? NSWindowController {
            _ = container  // 只是占位,SwiftUI 拿不到 ModelContext singleton
        }
        // 干脆直接 terminate,SwiftData 的 autosave 会兜底。
        NSApp.terminate(nil)
    }

    private func detachQuietly(_ mountPoint: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint, "-quiet"]
        try? detach.run()
        detach.waitUntilExit()
    }

    private func showDownloadError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("update.download.error.title",
            value: "Download failed", comment: "")
        // 把所有试过的源 + 错误一起呈现,让用户知道哪些试过了。然后给一个
        // "去 GitHub Release 手动下载"的按钮兜底。
        let triedURLs = downloadURLs.map { $0.absoluteString }.joined(separator: "\n")
        alert.informativeText = String(format:
            NSLocalizedString("update.download.error.body.format",
                value: "All download mirrors failed:\n%@\n\nLast error: %@\n\nYou can download manually from the release page.",
                comment: ""),
            triedURLs, message)
        // 第一个按钮 = default(回车);"打开 Release 页"作为推荐操作。
        alert.addButton(withTitle: NSLocalizedString("update.openReleasePage",
            value: "Open Release Page", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel",
            value: "Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn, let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func showDMGError() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("update.dmg.error.title",
            value: "Update package is invalid", comment: "")
        alert.informativeText = NSLocalizedString("update.dmg.error.message",
            value: "The downloaded DMG could not be mounted or doesn't contain FileLens.app. Please try downloading again from the website.",
            comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", value: "OK", comment: ""))
        alert.runModal()
        downloadComplete = false
        downloadedFileURL = nil
        isDownloading = false
        downloadProgress = 0
    }
}

// MARK: - Download delegate

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let onProgress: @Sendable (Double, Int64, Int64) -> Void
    let onComplete: @Sendable (URL) -> Void
    let onError: @Sendable (String) -> Void

    init(
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (URL) -> Void,
        onError: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            onError("HTTP \(http.statusCode)")
            return
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLens-update.dmg")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            do {
                try FileManager.default.copyItem(at: location, to: dest)
            } catch {
                onComplete(location)
                return
            }
        }
        // 校验下载完整性 —— 文件大小跟 HTTP Content-Length 对得上
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           let size = attrs[.size] as? Int64,
           let expected = (downloadTask.response as? HTTPURLResponse)?.expectedContentLength,
           expected > 0, size != expected {
            try? FileManager.default.removeItem(at: dest)
            onError("Incomplete download (\(size)/\(expected))")
            return
        }
        onComplete(dest)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64,
                    totalBytesWritten written: Int64,
                    totalBytesExpectedToWrite expected: Int64) {
        let total = expected > 0 ? expected : 1
        let progress = Double(written) / Double(total)
        onProgress(progress, written, expected)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        if let error = error { onError(error.localizedDescription) }
    }
}
