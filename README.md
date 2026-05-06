# FileLens

A non-destructive view layer for any folder on macOS. FileLens watches folders you choose and presents files grouped by user-defined rules and tags — without ever moving, renaming, or modifying the original files.

> Files stay where they are. FileLens just shows them through a different lens.

## Status

Pre-implementation. Design spec at `docs/superpowers/specs/2026-05-06-file-lens-design.md`.

## Stack

- macOS 14+ (Sonoma)
- SwiftUI + AppKit (NSPathControl, QLPreviewPanel)
- SwiftData
- QuickLookThumbnailing
- FSEvents

## Distribution

Direct DMG, dev signing. Not sandboxed in v1.
