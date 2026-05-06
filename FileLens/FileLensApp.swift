import SwiftUI
import SwiftData

@main
struct FileLensApp: App {
    let container: ModelContainer

    init() {
        do {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.FileLens"
            let storeURL = try StoreMigration.resolveStoreURL(bundleID: bundleID)
            let schema = Schema([Workspace.self, Rule.self, Condition.self, FileNode.self, FileTag.self])
            let config = ModelConfiguration(schema: schema, url: storeURL)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to init ModelContainer: \(error)")
        }
        // Note: do NOT call NSApp.* here — NSApplication is not yet initialized
        // at SwiftUI App.init() time. Apply appearance from .onAppear below.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    applyPersistedAppearance()
                    GlobalShortcuts.register()
                    // Migrate older installs: rules created before
                    // BuiltInRules.all() localized at creation time are
                    // stored with English keys and read awkwardly in the
                    // editor. This rewrites them once.
                    RuleNameMigration.runIfNeeded(container: container)
                    // Silent update probe — only nags if there's a newer
                    // release and we haven't checked in the last 24h.
                    UpdateService.checkInBackgroundIfNeeded()
                }
        }
        .modelContainer(container)
        .commands { FileLensCommands() }

        Settings {
            SettingsView()
        }
        .modelContainer(container)
    }

    private func applyPersistedAppearance() {
        let raw = UserDefaults.standard.string(forKey: "filelens.appearance") ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}
