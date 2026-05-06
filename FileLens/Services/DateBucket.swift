import Foundation

/// Finder-style date buckets for grouping files in the list view.
/// Buckets are coarse → finer over time: today, recent (3/7/15 days),
/// past month, then years.
enum DateBucket: Int, CaseIterable, Identifiable {
    case today
    case yesterday
    case last3Days
    case last7Days
    case last15Days
    case lastMonth
    case last3Months
    case last6Months
    case lastYear
    case older

    var id: Int { rawValue }

    var localizationKey: String {
        switch self {
        case .today:       return "bucket.today"
        case .yesterday:   return "bucket.yesterday"
        case .last3Days:   return "bucket.last3"
        case .last7Days:   return "bucket.last7"
        case .last15Days:  return "bucket.last15"
        case .lastMonth:   return "bucket.lastMonth"
        case .last3Months: return "bucket.last3Months"
        case .last6Months: return "bucket.last6Months"
        case .lastYear:    return "bucket.lastYear"
        case .older:       return "bucket.older"
        }
    }

    var localizedTitle: String {
        NSLocalizedString(localizationKey, value: localizationKey, comment: "Date bucket title")
    }

    static func bucket(for date: Date) -> DateBucket {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let now = Date.now
        if date > now { return .today }
        let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
        if days <= 3   { return .last3Days }
        if days <= 7   { return .last7Days }
        if days <= 15  { return .last15Days }
        if days <= 30  { return .lastMonth }
        if days <= 90  { return .last3Months }
        if days <= 180 { return .last6Months }
        if days <= 365 { return .lastYear }
        return .older
    }
}

