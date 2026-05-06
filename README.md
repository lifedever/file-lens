# FileLens

A non-destructive view layer for any folder on macOS. FileLens watches folders you choose and presents files grouped by user-defined rules and tags — without ever moving, renaming, or modifying the original files.

> Files stay where they are. FileLens just shows them through a different lens.

## v0.1.0 Features

- Multi-folder watch with FSEvents-driven live updates
- 12 built-in tag rules + user-defined custom rules + manual tags
- Three view modes: icon (⌘1) / list (⌘2) / gallery (⌘4), Finder-aligned shortcuts
- Quick Look (Space), drag-out to other apps, Reveal in Finder (⌘R), Move to Trash (⌘⌫)
- Inspector pane (⌘I) with metadata + tags
- Live search (⌘F) over file names
- Status bar with item count + total size
- Workspaces persist across launches via URL bookmarks
- en + 简体中文 localization
- **Non-destructive**: original files are never moved or modified (Move to Trash is the only physical action)

## Stack

- macOS 14+ (Sonoma)
- SwiftUI + AppKit (`QLPreviewPanel`, `NSOpenPanel`, `Quartz`)
- SwiftData
- QuickLookThumbnailing
- FSEvents
- xcodegen (project generation from `project.yml`)

## Run

```bash
# Build Debug + open the app:
./Scripts/dev.sh

# Build Release + package into a DMG:
./Scripts/release.sh 0.1.0
# → dist/FileLens-0.1.0.dmg
```

## Project Layout

```
project.yml                    # Source of truth for FileLens.xcodeproj
FileLens/                      # App sources
├── FileLensApp.swift          # @main + ModelContainer wiring
├── Models/                    # SwiftData @Model entities (Workspace, Rule, Condition, FileNode, FileTag)
├── Services/                  # Pure logic (RuleEngine, ConditionEvaluator), filesystem (FolderWatcher, FileIndexer), helpers
├── Views/                     # SwiftUI: ContentView, SidebarView, FileGridView, FileTableView, GalleryView, InspectorView, RuleEditorView, FirstRunRulePicker, EmptyStateView
└── Resources/Localizable.xcstrings   # en + zh-Hans
FileLensTests/                 # XCTest (RuleEngine, ConditionEvaluator, BuiltInRules, FileIndexer, BookmarkStore, KindClassifier, StoreMigration)
Scripts/                       # dev.sh, release.sh
docs/superpowers/              # specs/ + plans/
```

## Distribution

Direct DMG, dev signing (ad-hoc), not sandboxed in v1. The `bookmarkData` persistence is wired so a future sandbox migration is a single-flag change.
