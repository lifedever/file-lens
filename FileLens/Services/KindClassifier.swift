import Foundation
import UniformTypeIdentifiers

enum KindClassifier {
    /// Maps a UTType to one of the seven big-bucket strings used in FileNode.kind:
    /// "image", "movie", "audio", "document", "archive", "code", "text", "other".
    static func bucket(for type: UTType) -> String {
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .movie) { return "movie" }
        if type.conforms(to: .audio) { return "audio" }
        if type.conforms(to: .archive) { return "archive" }
        if type.conforms(to: .sourceCode) { return "code" }
        if type.conforms(to: .pdf) { return "document" }
        if type.conforms(to: .spreadsheet) || type.conforms(to: .presentation)
            || type.conforms(to: .compositeContent) { return "document" }
        if type.conforms(to: .plainText) || type.conforms(to: .text) { return "text" }
        return "other"
    }
}
