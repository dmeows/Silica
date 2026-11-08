import AppKit
import SwiftUI

/// Owns the NSTextView for one buffer. Kept alive per tab so undo history,
/// selection and scroll position survive switching tabs.
final class TextController: NSObject, NSTextViewDelegate {
    let scrollView: NSScrollView
    let textView: NSTextView
    weak var buffer: EditorBuffer?
    private var highlighter: SyntaxHighlighter?
    private var lineNumbers: LineNumberRulerView?

    init(text: String, language: SyntaxLanguage?) {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        super.init()

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

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.15
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph

        textView.string = text
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (text as NSString).length))
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

    /// Restyles the text in place; this doesn't touch undo or mark the file dirty.
    @objc private func fontSizeDidChange() {
        let size = EditorSettings.shared.fontSize
        let font = Self.font(ofSize: size)
        textView.font = font
        textView.typingAttributes[.font] = font
        lineNumbers?.setEditorFontSize(size)
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
