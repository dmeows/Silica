import AppKit
import SwiftUI

/// Owns the NSTextView for one buffer. Kept alive per tab so undo history,
/// selection and scroll position survive switching tabs.
final class TextController: NSObject, NSTextViewDelegate {
    let scrollView: NSScrollView
    let textView: EditorTextView
    weak var buffer: EditorBuffer?
    private var highlighter: SyntaxHighlighter?
    private var lineNumbers: LineNumberRulerView?

    init(text: String, language: SyntaxLanguage?) {
        // Built by hand: `EditorTextView.scrollableTextView()` returned a TextKit 1 view,
        // and the gutter and indent guides draw through TextKit 2.
        scrollView = NSScrollView()
        textView = EditorTextView(usingTextLayoutManager: true)
        super.init()

        let contentSize = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        scrollView.documentView = textView

        scrollView.drawsBackground = false
        // Trackpad and wheel scrolling still work; the bars are just never drawn.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        let fontSize = EditorSettings.shared.fontSize
        textView.font = Self.font(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 12)

        textView.string = text
        applyParagraphStyle(for: textView.font!)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = self

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView, editorFontSize: fontSize)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        lineNumbers = ruler

        if let language {
            highlighter = SyntaxHighlighter(textView: textView, language: language)
            highlighter?.highlightNow()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(fontSizeDidChange),
            name: .editorFontSizeDidChange, object: nil
        )
    }

    private static func font(ofSize size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Line spacing, plus tab stops every `EditorTextView.tabWidth` columns of the
    /// monospaced font, so tabs line up with space indentation and the indent guides.
    private func applyParagraphStyle(for font: NSFont) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.15
        paragraph.tabStops = []
        paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width
            * CGFloat(EditorTextView.tabWidth)
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        if let storage = textView.textStorage {
            // Directly on the storage, so it isn't an undoable edit.
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
    }

    /// Restyles the text in place; this doesn't touch undo or mark the file dirty.
    @objc private func fontSizeDidChange() {
        let size = EditorSettings.shared.fontSize
        let font = Self.font(ofSize: size)
        textView.font = font
        textView.typingAttributes[.font] = font
        applyParagraphStyle(for: font)
        lineNumbers?.setEditorFontSize(size)
        textView.needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        highlighter?.textDidChange()
        lineNumbers?.textDidChange()
        if buffer?.isDirty == false {
            buffer?.isDirty = true
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        lineNumbers?.setNeedsRedraw()
    }

    // MARK: Lines (shared with the Markdown preview)

    /// The 1-based line shown at the top of the editor.
    func topVisibleLine() -> Int {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return 1 }
        let y = max(0, textView.visibleRect.minY - textView.textContainerOrigin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return 1 }
        let offset = contentManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        let text = textView.string as NSString
        var line = 1
        var index = 0
        while index < min(offset, text.length) {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            guard NSMaxRange(range) <= offset else { break }
            line += 1
            index = NSMaxRange(range)
        }
        return line
    }

    /// Scrolls so `line` (1-based) is at the top; with `placingCursor`, also puts the
    /// insertion point at its start.
    func scroll(toLine line: Int, placingCursor: Bool = false) {
        let text = textView.string as NSString
        var offset = 0
        var current = 1
        while current < line, offset < text.length {
            offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
            current += 1
        }
        if placingCursor {
            textView.setSelectedRange(NSRange(location: offset, length: 0))
        }
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let location = contentManager.location(layoutManager.documentRange.location, offsetBy: offset),
              let range = NSTextRange(location: layoutManager.documentRange.location, end: location) else { return }
        layoutManager.ensureLayout(for: range)
        if let fragment = layoutManager.textLayoutFragment(for: location) {
            textView.scroll(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY))
        }
    }
}

/// Hosts whichever buffer's scroll view is active.
struct TextViewHost: NSViewRepresentable {
    let controller: TextController

    func makeNSView(context: Context) -> HostView {
        HostView()
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.show(controller)
    }

    final class HostView: NSView {
        private weak var current: NSScrollView?

        func show(_ controller: TextController) {
            let scrollView = controller.scrollView
            guard current !== scrollView else { return }
            current?.removeFromSuperview()
            scrollView.frame = bounds
            scrollView.autoresizingMask = [.width, .height]
            addSubview(scrollView)
            current = scrollView
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(controller.textView)
            }
        }
    }
}
