import Foundation

enum ConditionEvaluator {
    static func evaluate(file: FileNode, condition: Condition) -> Bool {
        switch condition.field {
        case "extension":  return evalExtension(file: file, op: condition.op, value: condition.value)
        case "name":       return evalName(file: file, op: condition.op, value: condition.value)
        case "size":       return evalSize(file: file, op: condition.op, value: condition.value)
        case "dateAdded":  return evalDate(file: file, op: condition.op, value: condition.value)
        case "kind":       return evalKind(file: file, op: condition.op, value: condition.value)
        default:           return false
        }
    }

    // MARK: extension

    private static func evalExtension(file: FileNode, op: String, value: String) -> Bool {
        let fileExt = file.ext.lowercased()
        switch op {
        case "is":       return fileExt == value.lowercased()
        case "isNot":    return fileExt != value.lowercased()
        case "isAnyOf":
            let exts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            return exts.contains(fileExt)
        default: return false
        }
    }

    // MARK: name

    private static func evalName(file: FileNode, op: String, value: String) -> Bool {
        switch op {
        case "contains":   return file.name.localizedCaseInsensitiveContains(value)
        case "startsWith": return file.name.lowercased().hasPrefix(value.lowercased())
        case "endsWith":   return file.name.lowercased().hasSuffix(value.lowercased())
        case "matches":
            guard let regex = try? NSRegularExpression(pattern: value) else { return false }
            let range = NSRange(file.name.startIndex..., in: file.name)
            return regex.firstMatch(in: file.name, range: range) != nil
        default: return false
        }
    }

    // MARK: size

    private static func evalSize(file: FileNode, op: String, value: String) -> Bool {
        switch op {
        case ">":
            guard let bytes = parseBytes(value) else { return false }
            return file.size > bytes
        case "<":
            guard let bytes = parseBytes(value) else { return false }
            return file.size < bytes
        case "between":
            let parts = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  let lo = parseBytes(parts[0]),
                  let hi = parseBytes(parts[1]) else { return false }
            return file.size >= lo && file.size <= hi
        default: return false
        }
    }

    /// Parses "500MB", "1.5GB", "100KB", "1024" (bytes default).
    static func parseBytes(_ s: String) -> Int64? {
        let trimmed = s.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Int64)] = [("GB", 1_000_000_000), ("MB", 1_000_000), ("KB", 1_000), ("B", 1)]
        for (suffix, mult) in units where trimmed.hasSuffix(suffix) {
            let numStr = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            if let d = Double(numStr) { return Int64(d * Double(mult)) }
        }
        return Int64(trimmed)
    }

    // MARK: dateAdded

    private static func evalDate(file: FileNode, op: String, value: String) -> Bool {
        switch op {
        case "inLastDays":
            guard let days = Int(value) else { return false }
            let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
            return file.dateAdded >= cutoff
        case "notInLastDays":
            guard let days = Int(value) else { return false }
            let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
            return file.dateAdded < cutoff
        case "before":
            guard let target = ISO8601DateFormatter().date(from: value) else { return false }
            return file.dateAdded < target
        case "after":
            guard let target = ISO8601DateFormatter().date(from: value) else { return false }
            return file.dateAdded > target
        default: return false
        }
    }

    // MARK: kind

    private static func evalKind(file: FileNode, op: String, value: String) -> Bool {
        switch op {
        case "is":       return file.kind == value
        case "isAnyOf":
            let kinds = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return kinds.contains(file.kind)
        default: return false
        }
    }
}
