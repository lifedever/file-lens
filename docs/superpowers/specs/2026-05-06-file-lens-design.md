# FileLens — Design Spec

**Date:** 2026-05-06
**Status:** Approved for implementation planning
**Target:** macOS 14+ (Sonoma)
**Distribution:** Direct DMG, dev signing, not sandboxed (v1)

## 1. Problem Statement

The Downloads folder (and other dumping-ground folders like Desktop) accumulate hundreds of files that the user has no time or willingness to manually organize. Existing tools fall into two camps:

- **Physical organizers (Hazel, Spotless)** automatically move files into category folders. Powerful, but the user must trust the rules and accept that files no longer live where they originally landed. The cost of a misconfigured rule is high (files in unexpected places).
- **Built-in tools (Finder Smart Folders)** are virtual but UX-limited and not optimized for the "triage a messy folder" workflow.

**FileLens fills the middle**: a non-destructive view layer. The user designates folders to monitor; FileLens reads them and presents files grouped by user-defined rules and tags. The original folder is never modified — files keep their physical location. The only physical action FileLens permits is "move to Trash" (explicit user action, single-file granularity).

## 2. Goals

- **Non-destructive by default**: file moves, renames, copies are out of scope. Only "Move to Trash" is allowed as a user-initiated action.
- **Familiar UX**: layout, shortcuts, and interactions match Finder as closely as possible to minimize learning curve.
- **Smooth performance** at 10k–100k file scale: virtualized rendering, cached thumbnails, debounced FSEvents.
- **Native components first**: prefer SwiftUI / AppKit system APIs over custom UI to maximize platform consistency.
- **Multi-folder support**: users can monitor any number of folders, each as an independent workspace with its own rules.
- **Tag-style classification**: a file may belong to multiple categories simultaneously. Tags come from rules (auto) or manual user assignment.
- **Zero-config first run**: ship with 12 built-in default rules covering common file types so the app is useful immediately without any setup.

## 3. Non-Goals (v1)

- Physical file mutation other than Trash (no move, copy, rename, content edit).
- Cross-workspace aggregation (e.g. "show all PDFs across all watched folders").
- LLM-based auto-tagging or natural-language rule generation. (Deferred to v2.)
- Content-based classification (PDF text, OCR, image content).
- Cross-platform (Windows / Linux / iOS).
- iCloud sync of rules or tags.
- Team-shared tag systems.
- "Run shell script" or other Hazel-style advanced actions.
- Browser extensions, mobile companion apps.
- App Store distribution (v1 is direct DMG only, but data model leaves a clean path to sandbox later).

## 4. Confirmed User Decisions

| Decision | Choice |
|---|---|
| App nature | Virtual view layer; physical files never moved |
| Categorization driver | User-defined rules + 12 built-in defaults |
| LLM integration | v2 (out of scope for v1) |
| Folder scope | Multi-folder, each an independent workspace with its own rules and tag set |
| Multi-category membership | Yes — a file can carry many tags simultaneously (tag-style) |
| Tag sources | Rules (auto) + user manual assignment |
| Tech stack | SwiftUI + AppKit + SwiftData + native APIs (no Tauri / Electron / cross-platform) |
| Distribution | Direct DMG, dev signing, non-sandboxed |
| Layout philosophy | Mirror Finder (sidebar + main content, ⌘1/2/4 view modes, ⌘R / ⌘⌫ / ⌘I shortcuts) |

## 5. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      SwiftUI App (macOS)                     │
│  NavigationSplitView                                         │
│    Sidebar          │  Content Detail                       │
│    (Workspaces /    │  (Grid / Table / Gallery)             │
│    Tags / System)   │  + Toolbar + Inspector                │
└──────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│                      Service Layer                           │
│  FolderWatcher  →  FileIndexer  →  RuleEngine                │
│  (FSEvents)        (metadata cache)  (rule eval → FileTag)   │
│                              │                               │
│              ThumbnailService (QLThumbnailGenerator + disk)  │
└──────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  SwiftData @ ~/Library/Application Support/<bundleID>/       │
│     Workspace ──┬── Rule ── Condition                        │
│                 └── FileNode ── FileTag                      │
└──────────────────────────────────────────────────────────────┘
```

### Data flow

1. **Add workspace**: user picks a folder via `NSOpenPanel` → bookmark stored → `Workspace` row created.
2. **Initial scan**: `FileIndexer` enumerates the folder via `FileManager.enumerator`, collecting metadata (name, ext, size, dateAdded, dateModified, kind) into `FileNode` rows. Runs in `Task.detached(priority: .userInitiated)`. Progress shown next to the sidebar workspace row.
3. **Rule evaluation**: `RuleEngine` evaluates each `FileNode` against all enabled `Rule`s for the workspace. Matches produce `FileTag` rows (source = `rule`).
4. **Live updates**: `FolderWatcher` (FSEvents) emits create/modify/rename/delete events. `FileIndexer` updates `FileNode` rows; `RuleEngine` re-evaluates only affected files.
5. **UI**: views use `@Query` to subscribe to SwiftData. Reactive updates flow naturally. UI never reaches into services directly — all state is derived from SwiftData.

## 6. Data Model (SwiftData)

```swift
@Model class Workspace {
    var id: UUID
    var name: String              // default = folder name, user-editable
    var folderPath: String        // for display
    var bookmarkData: Data        // URL.bookmarkData() — for path resilience across rename/move
    var rules: [Rule]
    var files: [FileNode]
    var createdAt: Date
}

@Model class Rule {
    var id: UUID
    var workspace: Workspace?
    var name: String              // tag name: "Installers", "Invoices"
    var color: String             // hex or system color name
    var enabled: Bool
    var priority: Int             // sidebar display order
    var combinator: String        // "all" | "any"
    var conditions: [Condition]
    var isBuiltIn: Bool           // built-ins are not deletable, but disable/rename/edit OK
}

@Model class Condition {
    var id: UUID
    var rule: Rule?
    var field: String     // "extension" | "name" | "size" | "dateAdded" | "kind"
    var op: String        // "is" | "isAnyOf" | "isNot" | "contains" | "matches"
                          // | "startsWith" | "endsWith" | ">" | "<" | "between"
                          // | "inLastDays" | "notInLastDays"
    var value: String     // serialized; parsed at evaluation per field
}

@Model class FileNode {
    var id: UUID
    var workspace: Workspace?
    var relativePath: String      // relative to workspace folder
    var name: String
    var ext: String               // lowercase
    var size: Int64
    var dateAdded: Date           // Spotlight kMDItemDateAdded
    var dateModified: Date
    var kind: String              // UTType identifier (e.g. "public.png", "public.movie")
    var tags: [FileTag]
    var lastSeenAt: Date          // updated on every scan; used for delete detection
    var isPresent: Bool           // false = soft-deleted (file gone but metadata kept)
    var rulesEvaluatedAt: Date?   // skip re-eval if rule set + metadata unchanged
    var fileResourceID: String?   // serialized URLResourceValues.fileResourceIdentifier, for rename tracking
}

@Model class FileTag {
    var id: UUID
    var file: FileNode?
    var name: String              // = rule.name (auto) or user-typed (manual)
    var source: String            // "rule" | "manual"
    var ruleID: UUID?             // populated when source == "rule"
}
```

### Storage path discipline

Per CLAUDE.md TaskTick #22 hard rule: **all SwiftData stores must live at `~/Library/Application Support/<bundleID>/default.store`**, never the bare Application Support root. `StoreMigration.swift` enforces this and provides a one-time migration if a future schema move is needed.

### Why FileTag is its own entity

A file may have:
- Multiple rule-sourced tags (matches several rules)
- Plus manual tags
- Same tag name from both sources possible

When a rule is deleted, only `source=="rule" && ruleID==<deleted>` tags are removed. Manual tags survive.

When a file is soft-deleted (`isPresent=false`), tags are retained — if the user drags the file back from Trash, FSEvents fires a create event; the indexer matches by `relativePath` and `fileResourceID`, restores `isPresent=true`, and the tags are immediately re-applied.

## 7. Rule System

### Field × Operator matrix

| Field | Operators | Value example |
|---|---|---|
| `extension` | `is`, `isAnyOf`, `isNot` | `dmg`, `dmg,pkg,exe` |
| `name` | `contains`, `matches`, `startsWith`, `endsWith` | `截屏\|Screenshot\|CleanShot` (regex with `matches`) |
| `size` | `>`, `<`, `between` | `500MB`, `100MB,1GB` |
| `dateAdded` | `inLastDays`, `notInLastDays`, `before`, `after` | `7`, `30`, ISO date |
| `kind` | `is`, `isAnyOf` | `image`, `image,video` (UTType big buckets) |

### Evaluation semantics

- `combinator = "all"`: every condition must be true for the file to match.
- `combinator = "any"`: any one condition true is enough.
- A file matching N enabled rules gets N `FileTag` rows (with `source=rule`).
- A file matching zero rules has no `FileTag` rows; it surfaces in the virtual "Uncategorized" view.

### Performance

Rule evaluation is metadata-only — never reads file content. For 10,000 files × 20 rules, eval cost is dominated by SwiftData round-trips, not CPU. Eval runs off the main actor; UI renders from `@Query` subscriptions.

`rulesEvaluatedAt` + a hash of the workspace's rule set lets us skip re-eval when nothing has changed since last run (e.g. on app relaunch with unchanged metadata and rules).

## 8. Built-in Default Rules (12)

Ships enabled by default; user can disable, rename conditions, or edit. Cannot be deleted.

| Tag | Conditions | Use case |
|---|---|---|
| 📦 Installers | `extension isAnyOf dmg,pkg,app` | DMG/PKG cluster |
| 🖼 Images | `kind is image` | png/jpg/heic/webp etc. |
| 🎬 Videos | `kind is movie` | mp4/mov/mkv etc. |
| 🎵 Audio | `kind is audio` | mp3/m4a/wav etc. |
| 📄 PDF | `extension is pdf` | Highest-frequency single ext, deserves own bucket |
| 📑 Documents | `extension isAnyOf doc,docx,xls,xlsx,ppt,pptx,key,pages,numbers,txt,md,rtf` | Office / iWork / plain-text |
| 🗜 Archives | `extension isAnyOf zip,rar,7z,tar,gz,bz2` | |
| 💻 Code | `extension isAnyOf js,ts,py,swift,rs,go,java,c,cpp,h,sh,json,yml,yaml,toml,html,css` | Source / config |
| 📸 Screenshots | `name matches ^(截屏\|Screenshot\|CleanShot\|截图)` | Screenshot tools |
| 🐳 Large files | `size > 500MB` | Disk-eaters |
| ✨ New arrivals | `dateAdded inLastDays 7` | Recent week |
| 🕰 Stale | `dateAdded notInLastDays 30` | Cleanup candidates |

Implicit (always on, hidden behind a toggle):

| Tag | Conditions | Behavior |
|---|---|---|
| ⏬ Downloading | `extension isAnyOf crdownload,download,part,partial` | Sidebar entry collapsed by default; main view items shown grayed-out / non-interactive |

## 9. UI Structure

Layout: `NavigationSplitView` with sidebar + main content + optional inspector. Mirrors Finder.

```
┌──────────────────────────────────────────────────────────────────┐
│ ◀ ▶ │ 📁 Downloads / 📦 Installers │ ⊞ ☰ ▦ │ ↕ │🔍│ ⓘ │  ← NSToolbar
├──────────────┬───────────────────────────────────────────────────┤
│ WORKSPACES   │                                                   │
│ ▸ Downloads  │   ┌────┐ ┌────┐ ┌────┐ ┌────┐                   │
│   Desktop    │   │ 📄 │ │ 📄 │ │ 🖼 │ │ 🎬 │                   │
│              │   └────┘ └────┘ └────┘ └────┘                   │
│ TAGS         │                                                   │
│ ● Installers │   Main = LazyVGrid (icon) /                      │
│ ● Images     │          Table (list) /                          │
│ ● PDF        │          QLPreview-based gallery                 │
│ ● Screenshots│                                                   │
│ ─────────    │                                                   │
│ SYSTEM       │                                                   │
│ ⊘ Uncategor. │                                                   │
│ 🗑 Trashed   │                                                   │
│ ➕ Add Folder│                                                   │
├──────────────┴───────────────────────────────────────────────────┤
│ 12 items · 1.2 GB                                              ← status bar
└──────────────────────────────────────────────────────────────────┘
```

### Sidebar sections

| Section | Content | Finder analog |
|---|---|---|
| Workspaces | Watched folders, with file count badge | Favorites |
| Tags | All enabled rules + manually-named tags for the selected workspace | Tags |
| System | "Uncategorized" + "Trashed" virtual views | iCloud / Recents |

Switching workspace dynamically refreshes the Tags section to that workspace's rule set.

### View modes

| Shortcut | Mode | Implementation |
|---|---|---|
| ⌘1 | Icon view | `LazyVGrid` + `QLThumbnailGenerator` thumbnails |
| ⌘2 | List view | SwiftUI `Table`, columns: Name / Size / Date Added / Tags / Kind, sortable, draggable widths |
| ⌘3 | Column view | Not implemented (no folder hierarchy in our model). Mapped to ⌘2 to absorb muscle memory. |
| ⌘4 | Gallery view | Large preview + thumbnail strip, optimized for image/video/PDF triage |

### Keyboard shortcuts (Finder-aligned)

| Action | Shortcut | API |
|---|---|---|
| Quick Look | `Space` / `⌘Y` | `QLPreviewPanel.shared` |
| Open in default app | `⌘O` / double-click | `NSWorkspace.open(URL)` |
| Reveal in Finder | `⌘R` | `NSWorkspace.activateFileViewerSelecting` |
| Move to Trash | `⌘⌫` | `FileManager.trashItem` |
| Toggle Inspector | `⌘I` | `.inspector` modifier |
| Select all | `⌘A` | automatic |
| Focus search | `⌘F` | `.searchable` |
| Switch view | `⌘1/2/4` | view-mode state |
| Multi-select | `⌘click` / `⇧click` | List/Table automatic |
| Drag out | drag | `.draggable { url }` → `NSItemProvider(object: NSURL)` |

### Right-click menu (per file)

- Reveal in Finder
- Open With ▸ (system Open With submenu, populated via `NSWorkspace.urlsForApplications(toOpen:)`)
- Quick Look
- Add Tag ▸ (existing tags + "New tag…")
- Remove Tag ▸ (only manual tags; rule-sourced tags can't be removed per-file — disable the rule instead)
- Move to Trash

### "Uncategorized" and "Trashed" virtual views

- **Uncategorized** lists all `FileNode`s where `isPresent=true` and no `FileTag` rows exist. This is the user's "I should give this a tag" pile.
- **Trashed** lists `FileNode`s where `isPresent=false`. The file no longer exists at the original path (moved to system Trash via FileLens or deleted externally). Tags are retained. If the user drags the file back from system Trash to its original location, FSEvents fires create → indexer matches by `relativePath` + `fileResourceID` → flips `isPresent=true` → file re-appears in its original tag views with all tags intact. There is no in-app "Restore" action in v1 (system Trash is the canonical recovery surface).

### Empty state / first-run

- Big "Add Folder" CTA
- Suggested default: `~/Downloads`
- After folder added: modal with the 12 built-in rules, all checked by default; user unchecks any they don't want before commit. Unchecked rules are not created (rather than created-and-disabled) to keep the rule list clean.

## 10. Native Components Map

| Use | Component / API |
|---|---|
| Main shell | `NavigationSplitView` (macOS 14+) |
| Sidebar | SwiftUI `List` + `Section` + `selection` binding |
| Toolbar | `Toolbar` modifier + `ToolbarItemGroup` (auto-produces NSToolbar) |
| Search | `.searchable(text:)` |
| List view | SwiftUI `Table` |
| Grid view | `LazyVGrid` + `ScrollView` (auto-virtualized) |
| Thumbnails | `QLThumbnailGenerator` + on-disk cache |
| Quick Look | `QLPreviewPanel.shared` (AppKit) |
| Drag out | `.draggable { url }` |
| Right-click menu | `.contextMenu` |
| Folder picker | `NSOpenPanel` + `URL.bookmarkData()` |
| Path bar | `NSPathControl` bridged into SwiftUI (toolbar center) |
| Inspector | `.inspector` modifier (macOS 14+) |
| FS watching | FSEvents (`FSEventStreamCreate` via Swift wrapper) |
| UTType big buckets | `UTType.image`, `.movie`, `.audio`, `.archive`, `.sourceCode`, `.text`, etc. via `URLResourceValues.contentType` |

## 11. Edge Cases

| Scenario | Handling |
|---|---|
| `.crdownload` / `.download` / `.partial` files | Matched by built-in `Downloading` rule. Sidebar entry collapsed by default; files grayed out and non-interactive in main view. |
| Watched folder externally deleted or renamed | Bookmark fails to resolve → workspace shows "⚠ Path unavailable" with "Relocate…" button (NSOpenPanel). |
| iCloud Drive cloud-only files | Metadata readable, but content unavailable → thumbnail generation fails → fall back to Kind icon. No download triggered. |
| Huge / unusual files (huge MKV, weird formats) | `QLThumbnailGenerator` invoked with 5s timeout; on timeout fall back to Kind icon. Result cached so we don't retry every render. |
| File mid-write (size growing or 0) | After FSEvents create/modify, debounce 1s. If size still changing after 1s, defer indexing further; cap retries. |
| Rename | FSEvents emits `(delete oldName, create newName)`. Indexer correlates via `URLResourceValues.fileResourceIdentifier` (inode-equivalent). On match, update `relativePath` on the existing FileNode and migrate FileTags. |
| File restored from Trash externally | FSEvents create → indexer finds existing FileNode with `isPresent=false` matching `relativePath` and `fileResourceID` → set `isPresent=true`, retain tags. |
| Overlapping / nested watched folders | Allowed. Same physical file produces independent FileNodes per workspace (key = workspaceID + relativePath). |
| Path with emoji / special chars | Use `URL` end-to-end, never `String` paths. |
| Extension casing | Always lowercase before comparison. |
| SwiftData schema migration | Use `SchemaMigrationPlan`. Store path strictly `<AppSupport>/<bundleID>/default.store`. |
| Backup | Not done in v1. The store is just a metadata index — losing it means re-scan, which is cheap. (Contrast with TaskTick where data is user-created.) |
| FSEvents events lost (rare but documented) | `lastSeenAt` reconciliation: on every full scan, files not touched get `isPresent=false`. Periodic full re-scan on workspace activate or every N minutes. |
| App relaunch | Restore each workspace bookmark, kick off lightweight re-scan to reconcile `lastSeenAt`. Existing FileNodes with cached metadata reused. |

## 12. Performance Plan

1. **Thumbnail two-tier cache**: `QLThumbnailGenerator.generateBestRepresentation` async + on-disk persistence at `~/Library/Caches/<bundleID>/thumbs/<sha256(absPath)>.png`. Survives app relaunch. Failure cached as a sentinel so we don't keep retrying broken files.
2. **Virtualized rendering**: `LazyVGrid` and `Table` only render visible cells. Tested target: 100k FileNodes, no jank on M-series hardware.
3. **FSEvents throttling**: stream latency 200ms (system-level coalescing) + secondary debounce 1s in our Swift wrapper before triggering batch index updates. Prevents unzip / `git clone` storms from hammering SwiftData.
4. **Background scan**: `Task.detached(priority: .userInitiated)` + `FileManager.enumerator`. Progress reported per N files (e.g. every 100) to a sidebar spinner.
5. **Rule evaluation skip**: hash of workspace's rule set + per-file `rulesEvaluatedAt` lets us skip eval when nothing has changed.
6. **Search**: simple in-memory filter on `name` for v1. With SwiftData `@Query` predicates this stays fast up to ~100k rows. Full-text indexing is v2.

## 13. Security, Sandbox, Distribution

- **Not sandboxed in v1.** Matches user's existing pattern (PasteMemo / TaskTick / ShotMemo all dev-signed DMG, non-sandboxed). Avoids the security-scoped bookmark complexity for this initial release.
- **`bookmarkData` field is reserved**: v1 stores plain `URL.bookmarkData()` (non-security-scoped) for resilience against folder rename / move. Future sandbox migration only requires changing the `.options` flag to `.withSecurityScope` — data model is unchanged.
- **Permissions required**: none beyond the user explicitly choosing folders via NSOpenPanel. Specifically, no Full Disk Access, no Accessibility, no Camera/Mic.
- **No network**. v1 has no LLM, no telemetry, no auto-update server check. (Auto-update via Sparkle can be considered separately and is not part of this spec.)
- **Distribution**: direct DMG, dev-signed. Follows `swift-ship-check` skill checklist.

## 14. Project Structure

```
file-lens/
├── FileLens.xcodeproj
├── FileLens/
│   ├── FileLensApp.swift
│   ├── Views/
│   │   ├── ContentView.swift           # NavigationSplitView shell
│   │   ├── SidebarView.swift           # Workspaces / Tags / System sections
│   │   ├── FileGridView.swift          # ⌘1
│   │   ├── FileTableView.swift         # ⌘2
│   │   ├── GalleryView.swift           # ⌘4
│   │   ├── InspectorView.swift         # ⌘I
│   │   ├── RuleEditorView.swift        # New / edit rule
│   │   └── EmptyStateView.swift        # First-run + "no workspace selected"
│   ├── Models/
│   │   ├── Workspace.swift
│   │   ├── Rule.swift
│   │   ├── Condition.swift
│   │   ├── FileNode.swift
│   │   └── FileTag.swift
│   ├── Services/
│   │   ├── FolderWatcher.swift         # FSEvents wrapper
│   │   ├── FileIndexer.swift           # Scan + metadata + delete reconciliation
│   │   ├── RuleEngine.swift            # Pure evaluation
│   │   ├── BookmarkStore.swift         # URL bookmark persistence
│   │   ├── ThumbnailService.swift      # QLThumbnailGenerator + disk cache
│   │   ├── BuiltInRules.swift          # 12 default rule definitions
│   │   └── StoreMigration.swift        # SwiftData path discipline (TaskTick #22)
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Localizable.xcstrings       # zh-Hans, en
│   └── Info.plist
├── FileLensTests/
│   ├── RuleEngineTests.swift
│   ├── ConditionEvaluatorTests.swift
│   ├── BuiltInRulesTests.swift
│   └── FileIndexerTests.swift
├── Scripts/
│   ├── dev.sh                          # Generated via dev-launcher skill
│   └── release.sh                      # DMG packaging per swift-ship-check
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-05-06-file-lens-design.md   # this document
└── README.md
```

## 15. Testing Strategy

### Unit (XCTest)

- **`RuleEngine`**: given a `FileNode` + rule set, asserts the produced tag set. Covers `combinator=all/any`, every (field, op) pair, edge values (zero size, empty name, ancient date).
- **`ConditionEvaluator`**: per-operator tests including boundaries (e.g. exactly N days, just above/below size threshold, regex with multibyte chars).
- **`BuiltInRules`**: fixture file metadata samples (e.g. `MyApp-1.0.dmg`, `IMG_4523.heic`, `截屏2026-05-06.png`, `report.pdf`, `bigvideo.mkv` at 1.2GB) → asserted expected tags.
- **`FileIndexer` rename detection**: simulated rename event flow → asserts `FileTag`s migrate to the renamed `FileNode`.

### Integration

- **`FolderWatcher → FileIndexer → SwiftData`**: temporary directory + scripted file create/modify/rename/delete via FileManager, asserting `FileNode` state and `isPresent` flips.
- **Workspace lifecycle**: add workspace → initial scan → relaunch → bookmark restored → re-scan reconciles `lastSeenAt`.

### UI (XCUITest, minimal)

Happy-path coverage only:
- Add a folder → workspace appears with file count.
- Switch workspace → tag list updates.
- ⌘1 / ⌘2 / ⌘4 view switching.
- Quick Look (`Space`) opens preview panel.
- Right-click → Move to Trash → file disappears from view.

## 16. Out of Scope (v1, restated)

- Physical move / copy / rename (only Trash is allowed)
- Cross-workspace aggregation
- LLM auto-tag / NL-to-rule
- Content indexing (PDF text, OCR)
- Windows / Linux / iOS
- iCloud sync of rules / tags
- Team-shared tags
- "Run script" / external action rules
- Browser extension / mobile app
- Auto-update infrastructure (handled separately if needed)

## 17. Future / v2 Hooks

- **LLM auto-tag** (option ① from brainstorm): rule pass first, then LLM tags untagged or under-tagged files. Toggle on per-workspace, BYO API key.
- **NL-to-rule** (option ②): "Group all my invoices" → LLM emits a `Rule` definition for user review.
- **Cross-workspace aggregation view**: optional global "All Workspaces" workspace that unions FileNodes.
- **Sandbox migration**: flip `bookmarkData` creation to `.withSecurityScope`, update entitlements; data model already supports this.
- **Sparkle auto-update**: integration when v1 ships externally.

## 18. Open Questions

None blocking. Items potentially worth revisiting before implementation:

- **Localization scope**: ship zh-Hans + en for v1 (per default in `Localizable.xcstrings`); add ja / others on-demand. Confirm at the start of implementation.
- **App icon design**: separate task; can be deferred to pre-release polish phase via `app-icon-generator` skill.
- **Telemetry**: deliberately none in v1. Revisit if there's demand for crash reporting (Sentry is in the user's MCP toolchain).
