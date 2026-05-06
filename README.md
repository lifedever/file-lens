<div align="center">
  <img src="icons/icon.png" width="128" height="128" alt="FileLens" />

  <h1>FileLens</h1>

  <p><b>A non-destructive view layer for any folder on macOS.</b></p>
  <p>Watch any folder, group files by tags — without ever moving the originals.</p>

  <p>
    <a href="https://github.com/lifedever/file-lens/releases/latest">
      <img src="https://img.shields.io/github/v/release/lifedever/file-lens?style=flat-square&label=download" alt="Download" />
    </a>
    <img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square" alt="macOS 14+" />
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT" />
    <a href="https://github.com/lifedever/file-lens/stargazers">
      <img src="https://img.shields.io/github/stars/lifedever/file-lens?style=flat-square" alt="Stars" />
    </a>
  </p>

  <p>
    English · <a href="README.zh-CN.md">简体中文</a>
  </p>
</div>

---

## What is FileLens?

Your `~/Downloads` is a graveyard. Hundreds of `.dmg`s, screenshots, PDFs, and `IMG_4523.png`s you never sort. Existing tools either physically move files (Hazel — risky if a rule misfires) or are too weak (Finder Smart Folders).

**FileLens fills the middle.** Point it at any folder; it tags every file by type / name / size / age, and gives you a Finder-style sidebar to slice the contents by tag. Original files **never move**. The only physical action FileLens ever takes is "Move to Trash" — and only when you click it.

## Features

- 🏷 **Auto-tag** with 13 built-in rules (Installers, Images, Screenshots, Large files, Stale…) + your own custom rules
- 📁 **Multi-folder workspaces** — watch as many folders as you want, each with its own rule set
- ⚡ **Live FSEvents updates** — new downloads appear instantly with the right tags
- 🔍 **Three view modes**: icon (⌘1), list (⌘2 with date grouping), gallery (⌘4)
- 👁 **Quick Look (Space)**, drag-out, Reveal in Finder (⌘R), Move to Trash (⌘⌫)
- 🎨 **Native macOS feel** — system file icons, Finder-aligned shortcuts, Light / Dark mode
- 🌐 **English + 简体中文** out of the box
- 🛡 **Non-destructive guarantee**: no rule ever moves, renames, or modifies your files

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
| Switch view (icon / list / gallery) | `⌘1` / `⌘2` / `⌘4` |
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

- **GitHub Sponsors:** <https://github.com/sponsors/lifedever>
- **Alipay / WeChat Pay:** see QR codes on the project home page

Or just hit the ⭐ button at the top — it really helps.
