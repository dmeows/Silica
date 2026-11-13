import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The rendered view of one Markdown or HTML buffer, kept alive with its tab so
/// switching back and forth is instant.
///
/// A Markdown page is HTML from `MarkdownHTMLRenderer`, styled to match the editor and
/// drawn on a transparent background so the glass card shows through. Scripts in the
/// document itself never run; Silica's own small script (scroll position, double-click)
/// runs in a separate script world. Relative images load from disk through the
/// `silica-preview:` scheme, links to project files open in Silica, and web links open
/// in the browser.
///
/// An HTML file is shown as a browser would show it: on its own background, with its
/// scripts running and the keyboard going to the page. It loads as a `file:` page, so
/// WebKit's rules for local files apply, as in Safari: the page can load the images,
/// styles and scripts around it, but its scripts can't read local files. The
/// `silica-preview:` scheme, which serves any file, isn't used for it.
final class MarkdownPreview: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    enum Format {
        case markdown
        case html

        /// The format a file previews as, if it has a preview.
        init?(url: URL) {
            if SyntaxLanguage(url: url) == .markdown {
                self = .markdown
            } else if ["html", "htm", "xhtml"].contains(url.pathExtension.lowercased()) {
                // Not every file highlighted as HTML (Vue, Svelte) is a page.
                self = .html
            } else {
                return nil
            }
        }

        /// What the editor shows instead of the preview, e.g. "Show Markdown".
        var sourceName: String {
            switch self {
            case .markdown: "Markdown"
            case .html: "HTML"
            }
        }
    }

    let webView: PreviewWebView
    let format: Format

    /// Opens another file in the project (a link to it was clicked).
    var onOpenFile: ((URL) -> Void)?
    /// Double-click: edit the source at this 1-based line.
    var onEditLine: ((Int) -> Void)?
    /// A character was typed; switch to the source and insert it.
    var onType: ((String) -> Void)?

    private let fileURL: URL
    /// The folder an HTML page may load files from.
    private let readAccessURL: URL
    private var pendingLine: Int?
    /// HTML to show once the web content process may read `readAccessURL` (see `show(html:)`).
    private var pendingHTML: String?
    /// Where to scroll an HTML page to once it has loaded.
    private var pendingScroll: CGPoint?
    /// Silica has just asked for the editor's text to load as the page. That load
    /// is the only one at the page's own URL that's let through, so a self-link,
    /// form or script can't swap the page for the file on disk.
    private var isLoadingPage = false
    /// The web content process has been given access to `readAccessURL`, which it
    /// keeps until it exits.
    private var hasReadAccess = false
    private var baseURL: URL {
        URL(string: Self.scheme + "://local" + Self.encodedPath(fileURL.deletingLastPathComponent().path(percentEncoded: false)))!
    }

    static let scheme = "silica-preview"

    /// `readAccessURL` is the folder an HTML page may load files from, which should
    /// contain `fileURL`; it defaults to the file's own folder.
    init(fileURL: URL, format: Format, readAccessURL: URL? = nil) {
        self.fileURL = fileURL
        self.format = format
        self.readAccessURL = readAccessURL ?? fileURL.deletingLastPathComponent()

        let configuration = WKWebViewConfiguration()
        switch format {
        case .markdown:
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: Self.scheme)
            configuration.userContentController.addUserScript(WKUserScript(
                source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
            ))
        case .html:
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        webView = PreviewWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self

        // An HTML page keeps the web view's own background, and the keyboard, as in a browser.
        guard format == .markdown else { return }
        // Through a weak proxy: the content controller retains its handlers.
        configuration.userContentController.add(WeakScriptHandler(self), contentWorld: .defaultClient, name: "silica")
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.onType = { [weak self] characters in self?.onType?(characters) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(syntaxThemeDidChange),
            name: .syntaxThemeDidChange, object: nil
        )
    }

    /// Swaps in the new code colors without reloading, so the scroll position stays.
    @objc private func syntaxThemeDidChange() {
        guard let data = try? JSONEncoder().encode(Self.css), let css = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("{ const style = document.querySelector('head > style'); if (style) style.textContent = \(css); }", in: nil, in: .defaultClient) { _ in }
    }

    /// Shows the buffer's current text. `line` is where the editor is scrolled to.
    func show(source: String, line: Int) {
        switch format {
        case .markdown: show(markdown: source, line: line)
        case .html: show(html: source)
        }
    }

    /// Renders `markdown` and, once loaded, scrolls to the block nearest `line`.
    private func show(markdown: String, line: Int) {
        pendingLine = line
        let body = MarkdownHTMLRenderer.render(markdown)
        webView.loadHTMLString(Self.page(body: body), baseURL: baseURL)
    }

    /// Shows `html` as if it were the file. The text comes from the editor, not the
    /// disk, so unsaved changes show and it's read in the editor's encoding: WebKit
    /// takes a file without a `<meta charset>` to be Latin-1.
    ///
    /// WebKit only lets an HTML string load local files once the process has been
    /// given access by loading a file URL. The first time, that's the folder itself,
    /// which shows nothing and runs nothing, and the page loads once it's done.
    private func show(html: String) {
        // Coming back to the same place in the page, as a Markdown preview comes back
        // to the editor's line. The page is still there from last time, if there was one.
        webView.evaluateJavaScript("[window.scrollX, window.scrollY]", in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            if let offset = (try? result.get()) as? [Double], offset.count == 2 {
                pendingScroll = CGPoint(x: offset[0], y: offset[1])
            }
            load(html: html)
        }
    }

    private func load(html: String) {
        if pendingHTML != nil {
            // Still being given access; show this text when it's done instead.
            pendingHTML = html
        } else if hasReadAccess {
            loadPage(html)
        } else {
            hasReadAccess = true
            pendingHTML = html
            webView.loadFileURL(readAccessURL, allowingReadAccessTo: readAccessURL)
        }
    }

    private func loadPage(_ html: String) {
        isLoadingPage = true
        webView.loadHTMLString(html, baseURL: fileURL)
    }

    /// Loads the page that was waiting for access to the folder. Loading the folder
    /// fails, but the process keeps the access.
    private func showPendingHTML() {
        guard let html = pendingHTML else { return }
        pendingHTML = nil
        loadPage(html)
    }

    /// The 1-based source line of the first block visible at the top.
    func topVisibleLine(_ completion: @escaping (Int) -> Void) {
        webView.evaluateJavaScript("silica.topLine()", in: nil, in: .defaultClient) { result in
            completion((try? result.get()) as? Int ?? 1)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showPendingHTML()
        if let scroll = pendingScroll, pendingHTML == nil {
            pendingScroll = nil
            webView.evaluateJavaScript("window.scrollTo(\(scroll.x), \(scroll.y))", in: nil, in: .defaultClient) { _ in }
        }
        guard let line = pendingLine else { return }
        pendingLine = nil
        webView.evaluateJavaScript("silica.scrollToLine(\(line))", in: nil, in: .defaultClient) { _ in }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        showPendingHTML()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        showPendingHTML()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Only the page itself loads in place (and subframes, e.g. an embedded video);
        // every other navigation is a link and is handled here instead.
        guard let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame != false,
              url.absoluteString != baseURL.absoluteString, url.scheme != "about",
              !loadsInPlace(url) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)

        if format == .html {
            // Only a click opens anything, not a page's script sending it elsewhere.
            guard navigationAction.navigationType == .linkActivated else { return }
            if url.isFileURL {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue {
                    onOpenFile?(URL(filePath: url.path(percentEncoded: false)))
                }
            } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        if url.scheme == Self.scheme {
            let path = url.path(percentEncoded: false)
            if let fragment = url.fragment, path == baseURL.path(percentEncoded: false) || path == fileURL.path(percentEncoded: false) {
                // An #anchor in this document.
                let id = fragment.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                webView.evaluateJavaScript("document.getElementById('\(id)')?.scrollIntoView()", in: nil, in: .defaultClient) { _ in }
                return
            }
            let target = URL(filePath: path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: target.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue {
                onOpenFile?(target)
            }
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        }
    }

    /// For an HTML file: the page Silica is loading, a place in it (`#anchor`), and
    /// the folder while it's loaded to give the process access. Any other navigation
    /// to the page itself would load the file from disk, without unsaved edits and
    /// in the wrong encoding, so it's cancelled with the rest.
    private func loadsInPlace(_ url: URL) -> Bool {
        guard format == .html, url.isFileURL else { return false }
        // A folder's URL may or may not end in a slash.
        func path(_ url: URL) -> String {
            let path = url.standardizedFileURL.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        if path(url) == path(fileURL), url.query == nil {
            if isLoadingPage, url.fragment == nil {
                isLoadingPage = false
                return true
            }
            // A jump within the page, which doesn't reload it.
            if url.fragment != nil { return true }
        }
        return pendingHTML != nil && path(url) == path(readAccessURL)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // A new process starts without the access the old one was given.
        hasReadAccess = false
        pendingHTML = nil
        isLoadingPage = false
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let line = message.body as? Int {
            onEditLine?(line)
        }
    }

    // MARK: Page

    private static func encodedPath(_ path: String) -> String {
        let directory = path.hasSuffix("/") ? path : path + "/"
        return directory.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? directory
    }

    private static func page(body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>\(css)</style></head>
        <body><article>\(body)</article></body></html>
        """
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }

    private static var tokenCSS: (light: String, dark: String) {
        var light = "", dark = ""
        let theme = EditorSettings.shared.syntaxTheme
        for kind in TokenKind.allCases {
            let pair = theme.hexPair(for: kind)
            light += ".tok-\(kind) { color: \(hex(pair.light)); }\n"
            dark += ".tok-\(kind) { color: \(hex(pair.dark)); }\n"
        }
        return (light, dark)
    }

    private static var css: String {
        let size = Int(EditorSettings.shared.fontSize) + 1
        // Code in the editor's font, when one is chosen in Settings.
        let codeFont = EditorSettings.shared.fontFamily.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\", " } ?? ""
        let link = EditorSettings.shared.syntaxTheme.linkPair
        let tokens = tokenCSS
        return """
        :root { color-scheme: light dark; }
        html, body { background: transparent; margin: 0; }
        body {
          font: \(size)px/1.6 -apple-system, BlinkMacSystemFont, sans-serif;
          color: rgba(0, 0, 0, 0.86);
          -webkit-font-smoothing: antialiased;
        }
        article { max-width: 860px; margin: 0 auto; padding: 24px 32px 48px; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.6em; font-weight: 650; }
        h1 { font-size: 1.9em; } h2 { font-size: 1.45em; } h3 { font-size: 1.2em; }
        h1, h2 { padding-bottom: 0.3em; border-bottom: 1px solid rgba(128, 128, 128, 0.25); }
        article > :first-child { margin-top: 0; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
        a { color: \(hex(link.light)); text-decoration: none; }
        a:hover { text-decoration: underline; }
        code, pre { font-family: \(codeFont)ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.88em; }
        :not(pre) > code { padding: 0.15em 0.35em; border-radius: 4px; background: rgba(128, 128, 128, 0.14); }
        pre { padding: 12px 14px; border-radius: 8px; background: rgba(128, 128, 128, 0.10); overflow-x: auto; line-height: 1.45; }
        blockquote { margin-left: 0; padding: 0 1em; border-left: 3px solid rgba(128, 128, 128, 0.35); color: rgba(0, 0, 0, 0.6); }
        ul, ol { padding-left: 1.6em; }
        li > p { margin: 0 0 0.4em; }
        li.task { list-style: none; margin-left: -1.3em; }
        li.task input { margin: 0 0.45em 0 0; vertical-align: -1px; }
        li.task > p:first-of-type { display: inline; }
        /* Leave a little room above whatever block the preview scrolls to. */
        [data-line] { scroll-margin-top: 20px; }
        /* No scroll bar, like the rest of Silica. */
        ::-webkit-scrollbar { display: none; }
        hr { border: none; border-top: 1px solid rgba(128, 128, 128, 0.3); margin: 1.6em 0; }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(128, 128, 128, 0.3); padding: 6px 12px; }
        th { font-weight: 600; background: rgba(128, 128, 128, 0.08); }
        img { max-width: 100%; }
        ::selection { background: rgba(64, 120, 242, 0.25); }
        \(tokens.light)
        @media (prefers-color-scheme: dark) {
          body { color: rgba(255, 255, 255, 0.88); }
          a { color: \(hex(link.dark)); }
          blockquote { color: rgba(255, 255, 255, 0.6); }
          \(tokens.dark)
        }
        """
    }

    /// Runs in Silica's own script world, not the document's.
    private static let script = """
    window.silica = {
      blocks() { return Array.from(document.querySelectorAll('[data-line]')); },
      scrollToLine(line) {
        let target = null;
        const blocks = this.blocks();
        for (const el of blocks) { if (+el.dataset.line <= line) target = el; else break; }
        if (target && target !== blocks[0]) target.scrollIntoView({ block: 'start' }); else window.scrollTo(0, 0);
      },
      topLine() {
        for (const el of this.blocks()) { if (el.getBoundingClientRect().bottom > 1) return +el.dataset.line; }
        return 1;
      }
    };
    document.addEventListener('dblclick', (event) => {
      const block = event.target.closest('[data-line]');
      window.webkit.messageHandlers.silica.postMessage(block ? +block.dataset.line : 1);
    });
    """
}

/// The preview's web view: printable keys hand control back to the editor, when
/// `onType` is set.
final class PreviewWebView: WKWebView {
    var onType: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control])
        if let onType, modifiers.isEmpty, let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
            onType(characters)
            return
        }
        // Space, arrows and page keys keep scrolling the preview.
        super.keyDown(with: event)
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Serves local files (images next to the document) to the preview.
private final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let data = try? Data(contentsOf: URL(filePath: url.path(percentEncoded: false))) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

/// Hosts a buffer's preview web view in the editor card.
struct MarkdownPreviewHost: NSViewRepresentable {
    let preview: MarkdownPreview

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if preview.webView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(to: container)
        }
    }

    private func attach(to container: NSView) {
        let webView = preview.webView
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        DispatchQueue.main.async {
            webView.window?.makeFirstResponder(webView)
        }
    }
}
