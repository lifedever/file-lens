import Foundation

/// Single source of truth for displaying a FileNode.kind big-bucket string.
/// Storage uses canonical English ("image", "movie", "audio"...) and we
/// translate at the display site via Localizable.xcstrings.
enum KindDisplay {
    static func localizedName(_ raw: String) -> String {
        NSLocalizedString("kind.\(raw)", value: raw.capitalized, comment: "Kind display name")
    }
}
