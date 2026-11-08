import AppKit
import Observation

extension Notification.Name {
    static let editorFontSizeDidChange = Notification.Name("EditorFontSizeDidChange")
}

/// App-wide editor preferences, saved in UserDefaults.
@Observable
final class EditorSettings {
    static let shared = EditorSettings()

    static let defaultFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 9...36
    private static let fontSizeKey = "editorFontSize"

    /// Font size of the editor text; the line-number gutter scales with it.
    private(set) var fontSize: CGFloat

    var canIncreaseFontSize: Bool { fontSize < Self.fontSizeRange.upperBound }
    var canDecreaseFontSize: Bool { fontSize > Self.fontSizeRange.lowerBound }
    var isDefaultFontSize: Bool { fontSize == Self.defaultFontSize }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored > 0 ? Self.clamped(CGFloat(stored)) : Self.defaultFontSize
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

    /// Lets ⌘= (no Shift) zoom in too, the way most apps treat it.
    ///
    /// The View menu's "Increase Font Size" item is bound to ⌘+, which on a US
    /// keyboard needs Shift; menus can't also match the unshifted key.
    func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command, event.charactersIgnoringModifiers == "=", let self else { return event }
            self.increaseFontSize()
            return nil
        }
    }
}
