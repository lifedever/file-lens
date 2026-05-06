import Foundation
import SwiftData

/// One-time migration that rewrites rule names from their English
/// localization keys ("Documents", "Images", …) to the user's localized
/// form ("文档", "图片", …). Anything created after the BuiltInRules
/// localization fix already uses localized names, so this only touches
/// stale data from older installs.
///
/// We migrate FileTag.name in lockstep so tag-count lookups continue to
/// match against the renamed rules.
enum RuleNameMigration {
    private static let migratedKey = "filelens.ruleNamesMigrated.v1"

    /// English keys shipped with `BuiltInRules` historically. Names that
    /// match one of these are considered "untranslated" and get rewritten
    /// to their localized form via NSLocalizedString.
    private static let knownKeys: Set<String> = [
        "Installers", "Images", "Videos", "Audio", "PDF",
        "Documents", "Archives", "Code", "Screenshots",
        "Large files", "New arrivals", "Stale", "Downloading"
    ]

    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }

        let context = ModelContext(container)
        var changed = false

        if let rules = try? context.fetch(FetchDescriptor<Rule>()) {
            for rule in rules where knownKeys.contains(rule.name) {
                rule.name = NSLocalizedString(rule.name, value: rule.name, comment: "")
                changed = true
            }
        }

        if let tags = try? context.fetch(FetchDescriptor<FileTag>()) {
            for tag in tags where knownKeys.contains(tag.name) {
                tag.name = NSLocalizedString(tag.name, value: tag.name, comment: "")
                changed = true
            }
        }

        if changed { try? context.save() }
        defaults.set(true, forKey: migratedKey)
    }
}
