import Foundation

enum BuiltInRules {
    /// All default rules shipped with FileLens. Order = display priority (lower = higher).
    /// Each call returns fresh `Rule`/`Condition` instances; safe to call per workspace.
    static func all() -> [Rule] {
        return [
            rule("Installers",   "#3B82F6", priority:  0, [c("extension", "isAnyOf", "dmg,pkg,app")]),
            rule("Images",       "#10B981", priority: 10, [c("kind", "is", "image")]),
            rule("Videos",       "#EF4444", priority: 20, [c("kind", "is", "movie")]),
            rule("Audio",        "#F59E0B", priority: 30, [c("kind", "is", "audio")]),
            rule("PDF",          "#DC2626", priority: 40, [c("extension", "is", "pdf")]),
            rule("Documents",    "#8B5CF6", priority: 50,
                 [c("extension", "isAnyOf", "doc,docx,xls,xlsx,ppt,pptx,key,pages,numbers,txt,md,rtf")]),
            rule("Archives",     "#6B7280", priority: 60, [c("extension", "isAnyOf", "zip,rar,7z,tar,gz,bz2")]),
            rule("Code",         "#059669", priority: 70,
                 [c("extension", "isAnyOf",
                    "js,ts,py,swift,rs,go,java,c,cpp,h,sh,json,yml,yaml,toml,html,css")]),
            rule("Screenshots",  "#EC4899", priority: 80,
                 [c("name", "matches", "^(截屏|Screenshot|CleanShot|截图)")]),
            rule("Large files",  "#F97316", priority: 90, [c("size", ">", "500MB")]),
            rule("New arrivals", "#0EA5E9", priority: 100, [c("dateAdded", "inLastDays", "7")]),
            rule("Stale",        "#9CA3AF", priority: 110, [c("dateAdded", "notInLastDays", "30")]),
            rule("Downloading",  "#A3A3A3", priority: 999,
                 [c("extension", "isAnyOf", "crdownload,download,part,partial")]),
        ]
    }

    private static func rule(
        _ key: String,
        _ color: String,
        priority: Int,
        _ conditions: [Condition]
    ) -> Rule {
        // Localize the name at creation time, so a Chinese-system user gets
        // 图片/音频/视频… as the actual stored name. Once stored, users can
        // freely rename like any user-defined rule — no key→display mapping
        // is needed at render time.
        let localized = NSLocalizedString(key, value: key, comment: "Built-in rule name")
        let r = Rule(name: localized, color: color, enabled: true, priority: priority,
                     combinator: "any", isBuiltIn: true)
        for cnd in conditions { r.conditions.append(cnd) }
        return r
    }

    private static func c(_ field: String, _ op: String, _ value: String) -> Condition {
        Condition(field: field, op: op, value: value)
    }

    /// Map from the English key to its description string-catalog key.
    /// Kept private so the lookup forced through `descriptionKey(forBuiltInRuleNamed:)`,
    /// which knows how to reverse the English ↔ localized name match.
    private static let descriptionKeys: [String: String] = [
        "Installers":   "rule.Installers.desc",
        "Images":       "rule.Images.desc",
        "Videos":       "rule.Videos.desc",
        "Audio":        "rule.Audio.desc",
        "PDF":          "rule.PDF.desc",
        "Documents":    "rule.Documents.desc",
        "Archives":     "rule.Archives.desc",
        "Code":         "rule.Code.desc",
        "Screenshots":  "rule.Screenshots.desc",
        "Large files":  "rule.Large.desc",
        "New arrivals": "rule.NewArrivals.desc",
        "Stale":        "rule.Stale.desc",
        "Downloading":  "rule.Downloading.desc",
    ]

    /// Human-readable example/description for a built-in rule. Accepts either
    /// the English key or its localized form, so the lookup keeps working
    /// after `BuiltInRules.all()` started returning rules with localized
    /// names (otherwise nothing but PDF would match in zh-Hans).
    static func descriptionKey(forBuiltInRuleNamed name: String) -> String? {
        if let key = descriptionKeys[name] { return key }
        // Reverse lookup: does the input match the localized form of any key?
        for (englishKey, descKey) in descriptionKeys {
            let localized = NSLocalizedString(englishKey, value: englishKey, comment: "")
            if name == localized { return descKey }
        }
        return nil
    }
}
