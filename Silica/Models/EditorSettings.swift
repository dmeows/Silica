import AppKit
import Observation

extension Notification.Name {
    static let editorFontSizeDidChange = Notification.Name("EditorFontSizeDidChange")
    static let editorWrapDidChange = Notification.Name("EditorWrapDidChange")
}

/// App-wide editor preferences, saved in UserDefaults.
@Observable
final class EditorSettings {
    static let shared = EditorSettings()

    static let defaultFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 9...36
    private static let fontSizeKey = "editorFontSize"
    private static let wrapsLinesKey = "editorWrapsLines"

    /// Font size of the editor text; the line-number gutter scales with it.
    private(set) var fontSize: CGFloat

    /// Long lines wrap to the editor's width; off, they scroll sideways.
    var wrapsLines: Bool {
        didSet {
            guard wrapsLines != oldValue else { return }
            // Stored only when off, so the default stays on.
            if wrapsLines {
                UserDefaults.standard.removeObject(forKey: Self.wrapsLinesKey)
            } else {
                UserDefaults.standard.set(false, forKey: Self.wrapsLinesKey)
            }
            NotificationCenter.default.post(name: .editorWrapDidChange, object: self)
        }
    }

    var canIncreaseFontSize: Bool { fontSize < Self.fontSizeRange.upperBound }
    var canDecreaseFontSize: Bool { fontSize > Self.fontSizeRange.lowerBound }
    var isDefaultFontSize: Bool { fontSize == Self.defaultFontSize }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored > 0 ? Self.clamped(CGFloat(stored)) : Self.defaultFontSize
        wrapsLines = UserDefaults.standard.object(forKey: Self.wrapsLinesKey) as? Bool ?? true
    }

    func increaseFontSize() { setFontSize(fontSize + 1) }
    func decreaseFontSize() { setFontSize(fontSize - 1) }
    func resetFontSize() { setFontSize(Self.defaultFontSize) }

    private func setFontSize(_ size: CGFloat) {
        let size = Self.clamped(size)
        guard size != fontSize else { return }
        fontSize = size
        if size == Self.defaultFontSize {
            UserDefaults.standard.removeObject(forKey: Self.fontSizeKey)
        } else {
            UserDefaults.standard.set(Double(size), forKey: Self.fontSizeKey)
        }
        NotificationCenter.default.post(name: .editorFontSizeDidChange, object: self)
    }

    private static func clamped(_ size: CGFloat) -> CGFloat {
        min(max(size.rounded(), fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    // MARK: Keyboard

    private var keyMonitor: Any?

    /// Lets ⌘= (no Shift) zoom in too, the way most apps treat it, and ⌥Z toggle
    /// word wrap.
    ///
    /// The View menu's "Increase Font Size" item is bound to ⌘+, which on a US
    /// keyboard needs Shift; menus can't also match the unshifted key.
    func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard let self else { return event }
            if flags == .command, event.charactersIgnoringModifiers == "=" {
                self.increaseFontSize()
                return nil
            }
            // ⌥Z, as in VS Code. Also in the View menu, but an editor with focus would
            // otherwise type "Ω".
            if flags == .option, event.charactersIgnoringModifiers?.lowercased() == "z",
               event.window?.attachedSheet == nil, NSApp.modalWindow == nil,
               event.window?.firstResponder is EditorTextView {
                self.wrapsLines.toggle()
                return nil
            }
            return event
        }
    }
}
