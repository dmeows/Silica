import AppKit
import Foundation
import Observation

/// One open file. Text files own a live `TextController` so each tab keeps
/// its own undo history, selection and scroll position.
@Observable
final class EditorBuffer: Identifiable {
    enum Content {
        case text(TextController)
        case binary
        case tooLarge(Int64)
        case unreadable(String)
    }

    let url: URL
    let content: Content
    let encoding: String.Encoding

    var isDirty = false

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var textController: TextController? {
        if case .text(let controller) = content { controller } else { nil }
    }

    private static let maxFileSize: Int64 = 20 * 1024 * 1024

    init(url: URL) {
        self.url = url

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if size > Self.maxFileSize {
            content = .tooLarge(size)
            encoding = .utf8
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            content = .unreadable(error.localizedDescription)
            encoding = .utf8
            return
        }

        guard !Self.looksBinary(data), let (text, encoding) = Self.decode(data) else {
            content = .binary
            encoding = .utf8
            return
        }

        self.encoding = encoding
        let controller = TextController(text: text, language: SyntaxLanguage(url: url))
        content = .text(controller)
        controller.buffer = self
    }

    func save() throws {
        guard let controller = textController else { return }
        try controller.textView.string.write(to: url, atomically: true, encoding: encoding)
        isDirty = false
    }

    private static func looksBinary(_ data: Data) -> Bool {
        data.prefix(8192).contains(0)
    }

    private static func decode(_ data: Data) -> (String, String.Encoding)? {
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        var converted: NSString?
        var usedLossy: ObjCBool = false
        let raw = NSString.stringEncoding(
            for: data,
            encodingOptions: [.allowLossyKey: false],
            convertedString: &converted,
            usedLossyConversion: &usedLossy
        )
        guard raw != 0, let converted else { return nil }
        return (converted as String, String.Encoding(rawValue: raw))
    }
}
