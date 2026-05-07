# FileLens

<div align="center">

<img src="icons/icon.png" width="220" alt="FileLens" />

### FileLens

**A non-destructive view layer for any folder on macOS.**
Watch any folder, group files by tags — without ever moving the originals.

![Latest](https://img.shields.io/github/v/release/lifedever/file-lens?label=Latest&color=brightgreen&style=flat-square)
![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square)
![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![stars](https://img.shields.io/github/stars/lifedever/file-lens?style=flat-square)

[⬇ **Download Latest**](https://github.com/lifedever/file-lens/releases/latest) | [💖 **Sponsor**](https://www.lifedever.com)

[中文文档](README.zh-CN.md)

---

</div>

## What is FileLens?

Your `~/Downloads` accumulates hundreds of files — `.dmg`s, screenshots, PDFs, `IMG_4523.png`s — that you never sort. Existing tools either physically move them (Hazel — risky if a rule misfires) or are too weak (Finder Smart Folders).

**FileLens does neither.** It tags every file by type / name / size / age inside the app, and gives you a Finder-style sidebar to slice the contents by tag — without ever touching the files themselves. The only physical action FileLens ever takes is "Move to Trash", and only when you click it.

<p align="center">
  <img src="web/screenshot-3.png" alt="FileLens screenshot" width="800">
</p>

## Features

- 🏷 **Auto-tag** — 14 built-in rules (Folders / Installers / Images / Screenshots / Large files / Stale…) plus your own custom rules
- 📁 **Multi-folder** — watch any number of folders, each with its own rule set; right-click any folder for per-folder recursion / depth / exclusion settings
- ⚡ **Live FSEvents updates** — new downloads appear instantly with the right tags
- 🔍 **Two view modes** — icon (⌘1, with size slider in the status bar), list (⌘2 with date grouping)
- 👁 **Native interactions** — Quick Look (Space), drag-out, Reveal in Finder (⌘R), Move to Trash (⌘⌫)
- 🎨 **Native macOS feel** — system file icons, Finder-aligned shortcuts, Light / Dark / System
- 🌐 **English + 简体中文** out of the box
- 🛡 **Non-destructive guarantee** — no rule ever moves, renames, or modifies your files

## Install

[**↓ Download the latest DMG**](https://github.com/lifedever/file-lens/releases/latest)

| Mac | File |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | `FileLens-X.Y.Z-arm64.dmg` |
| Intel | `FileLens-X.Y.Z-x86_64.dmg` |

Drag `FileLens.app` into `/Applications`. Because the app uses ad-hoc dev signing, on first launch macOS may say "the app is damaged". One-time fix:

```bash
sudo xattr -rd com.apple.quarantine /Applications/FileLens.app
```

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Quick Look | `Space` |
| Open in default app | `⌘↩` |
| Reveal in Finder | `⌘R` |
| Move to Trash | `⌘⌫` |
| Toggle Inspector | `⌘I` |
| Search | `⌘F` |
| Switch view (icon / list) | `⌘1` / `⌘2` |
| Settings | `⌘,` |

## Build from source

Requirements: macOS 14+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen), [librsvg](https://gitlab.gnome.org/GNOME/librsvg).

```bash
brew install xcodegen librsvg
git clone https://github.com/lifedever/file-lens.git
cd file-lens
xcodegen generate
./Scripts/dev.sh                       # Debug + open
./Scripts/release.sh 0.1.0 arm64       # Release DMG (or x86_64 / universal)
```

## Tech stack

macOS 14+ · SwiftUI + AppKit · SwiftData · QuickLookThumbnailing · FSEvents

## License

[MIT](LICENSE) © lifedever

---

## ☕ Donate

If FileLens saves you time, please consider supporting development:

- **Sponsor / Donate:** <https://www.lifedever.com>
- **Alipay / WeChat Pay:** see QR codes on the project home page

Or just hit the ⭐ button at the top — it really helps.
