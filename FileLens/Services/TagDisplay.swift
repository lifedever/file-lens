import Foundation

/// Single source of truth for displaying tag names to the user.
/// Built-in rule names are stored in their canonical English form
/// (Installers / Images / etc.) and translated via Localizable.xcstrings
/// at the display site. User-typed tag names pass through unchanged.
enum TagDisplay {
    static func localizedName(_ raw: String) -> String {
        NSLocalizedString(raw, value: raw, comment: "Tag display name")
    }
}
