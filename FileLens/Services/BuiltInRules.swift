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
        _ name: String,
        _ color: String,
        priority: Int,
        _ conditions: [Condition]
    ) -> Rule {
        let r = Rule(name: name, color: color, enabled: true, priority: priority,
                     combinator: "any", isBuiltIn: true)
        for cnd in conditions { r.conditions.append(cnd) }
        return r
    }

    private static func c(_ field: String, _ op: String, _ value: String) -> Condition {
        Condition(field: field, op: op, value: value)
    }

    /// Human-readable example/description for a built-in rule.
    /// Returns nil for user-created rule names.
    static func descriptionKey(forBuiltInRuleNamed name: String) -> String? {
        switch name {
        case "Installers":   return "rule.Installers.desc"
        case "Images":       return "rule.Images.desc"
        case "Videos":       return "rule.Videos.desc"
        case "Audio":        return "rule.Audio.desc"
        case "PDF":          return "rule.PDF.desc"
        case "Documents":    return "rule.Documents.desc"
        case "Archives":     return "rule.Archives.desc"
        case "Code":         return "rule.Code.desc"
        case "Screenshots":  return "rule.Screenshots.desc"
        case "Large files":  return "rule.Large.desc"
        case "New arrivals": return "rule.NewArrivals.desc"
        case "Stale":        return "rule.Stale.desc"
        case "Downloading":  return "rule.Downloading.desc"
        default:             return nil
        }
    }
}
