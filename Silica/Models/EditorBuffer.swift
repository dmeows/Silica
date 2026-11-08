import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// One open file. Text files own a live `TextController` so each tab keeps
/// its own undo history, selection and scroll position.
@Observable
final class EditorBuffer: Identifiable {
    enum Content {
        case text(TextController)
        case image(ImageFile)
        case binary
        case tooLarge(Int64)
        case unreadable(String)
    }

    let url: URL
    let content: Content
    let encoding: String.Encoding

    var isDirty = false

    /// Markdown files can switch between their source and a rendered preview.
    let isMarkdown: Bool
    private(set) var isShowingPreview = false
    /// Created the first time the preview is shown, then kept with the tab.
    @ObservationIgnored private(set) var preview: MarkdownPreview?
    /// Opens a project file a preview link points to.
    @ObservationIgnored var openFile: ((URL) -> Void)?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var textController: TextController? {
        if case .text(let controller) = content { controller } else { nil }
    }

    /// A decoded image shown read-only in the editor card.
    struct ImageFile {
        let image: NSImage
        let pixelSize: CGSize
        let byteCount: Int64
        /// e.g. "PNG", "JPEG", "WebP".
        let format: String
    }

    private static let maxFileSize: Int64 = 20 * 1024 * 1024
    private static let maxImageSize: Int64 = 200 * 1024 * 1024

    init(url: URL) {
        self.url = url
        self.isMarkdown = SyntaxLanguage(url: url) == .markdown

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        if Self.isImage(url) {
            encoding = .utf8
            if size > Self.maxImageSize {
                content = .tooLarge(size)
            } else if let image = Self.loadImage(url, byteCount: size) {
                content = .image(image)
            } else {
                content = .unreadable("“\(url.lastPathComponent)” couldn’t be decoded as an image.")
            }
            return
        }

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

    // MARK: Markdown preview

    func togglePreview() {
        setShowingPreview(!isShowingPreview)
    }

    /// Switches between source and preview, keeping roughly the same place in the
    /// document. `editLine` (from a double-click) puts the cursor on that source line.
    func setShowingPreview(_ show: Bool, editLine: Int? = nil) {
        guard isMarkdown, let controller = textController, show != isShowingPreview else { return }
        if show {
            let preview = self.preview ?? makePreview(for: controller)
            self.preview = preview
            preview.show(markdown: controller.textView.string, line: controller.topVisibleLine())
            isShowingPreview = true
        } else if let editLine {
            isShowingPreview = false
            DispatchQueue.main.async { controller.scroll(toLine: editLine, placingCursor: true) }
        } else {
            preview?.topVisibleLine { [weak self] line in
                self?.isShowingPreview = false
                DispatchQueue.main.async { controller.scroll(toLine: line) }
            }
        }
    }

    private func makePreview(for controller: TextController) -> MarkdownPreview {
        let preview = MarkdownPreview(fileURL: url)
        preview.onOpenFile = { [weak self] url in self?.openFile?(url) }
        preview.onEditLine = { [weak self] line in self?.setShowingPreview(false, editLine: line) }
        preview.onType = { [weak self] characters in
            guard let self else { return }
            self.isShowingPreview = false
            // Once the editor is back in the card, type the character there.
            DispatchQueue.main.async {
                controller.textView.insertText(characters, replacementRange: controller.textView.selectedRange())
            }
        }
        return preview
    }

    func save() throws {
        guard let controller = textController else { return }
        try controller.textView.string.write(to: url, atomically: true, encoding: encoding)
        isDirty = false
    }

    /// Raster image formats ImageIO can decode. SVG stays text so it can be edited.
    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .svg)
    }

    private static func loadImage(_ url: URL, byteCount: Int64) -> ImageFile? {
        guard let image = NSImage(contentsOf: url), image.isValid else { return nil }
        var pixelSize = CGSize(width: image.size.width, height: image.size.height)
        var format = url.pathExtension.uppercased()
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                pixelSize = CGSize(width: width, height: height)
            }
            if let typeID = CGImageSourceGetType(source) as String?,
               let name = UTType(typeID)?.preferredFilenameExtension {
                format = name == "jpeg" ? "JPEG" : name == "webp" ? "WebP" : name.uppercased()
            }
        }
        return ImageFile(image: image, pixelSize: pixelSize, byteCount: byteCount, format: format)
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
