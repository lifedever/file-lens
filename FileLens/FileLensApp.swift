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

        // Apply persisted appearance preference (Light/Dark/System) at launch.
        let raw = UserDefaults.standard.string(forKey: "filelens.appearance") ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)

        Settings {
            SettingsView()
        }
        .modelContainer(container)
    }
}
