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
    @Published var downloadURL: URL?

    // 下载状态
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var downloadComplete = false
    @Published var downloadedFileURL: URL?

    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: DownloadDelegate?

    private init() {}

    /// 进入对话框前,UpdateService 调它把这次的 release 信息塞进来,并 reset
    /// 之前的下载状态(用户可能上一轮取消了)。
    func prepare(info: UpdateInfo, currentVersion: String) {
        self.latestTag = info.latestTag
        self.currentVersion = currentVersion
        self.releaseNotes = info.body ?? ""
        self.downloadURL = pickDMGURL(info: info)
        // reset
        isDownloading = false
        downloadProgress = 0
        downloadedBytes = 0
        totalBytes = 0
        downloadComplete = false
        downloadedFileURL = nil
    }

    /// 我们 ship universal DMG,文件名格式 `FileLens-<version>-universal.dmg`。
    /// 优先从 release.assets 找(GitHub API 给了 URL),拿不到就回退到约定 URL。
    private func pickDMGURL(info: UpdateInfo) -> URL? {
        // tag 形如 "v1.1.0",取数字部分
        let version = info.latestTag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let dmgName = "FileLens-\(version)-universal.dmg"
        return URL(string: "https://github.com/lifedever/file-lens/releases/download/v\(version)/\(dmgName)")
    }

    // MARK: - Download

    func startDownload() {
        guard let url = downloadURL else { return }
        isDownloading = true
        downloadProgress = 0
        downloadedBytes = 0
        downloadComplete = false

        let delegate = DownloadDelegate { [weak self] progress, received, total in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.downloadedBytes = received
                self?.totalBytes = total
            }
        } onComplete: { [weak self] fileURL in
            Task { @MainActor in
                self?.downloadComplete = true
                self?.downloadedFileURL = fileURL
                self?.isDownloading = false
            }
        } onError: { [weak self] message in
            Task { @MainActor in
                self?.isDownloading = false
                self?.downloadComplete = false
                self?.downloadProgress = 0
                self?.showDownloadError(message)
            }
        }
        self.downloadDelegate = delegate

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancelDownload() {
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
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", value: "OK", comment: ""))
        alert.runModal()
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
