import AppKit
import Combine
import SwiftUI

/// The workspace whose window is key, for menu commands and shortcuts to act on.
final class KeyWorkspace: ObservableObject {
    static let shared = KeyWorkspace()
    @Published var current: WorkspaceModel?
    private init() {}

    private var keyMonitor: Any?

    /// ⇧⌘V toggles a Markdown tab between source and preview. Handled here as well
    /// as in the View menu because a menu item bound to ⇧⌘V didn't reliably win
    /// over Edit > Paste (⌘V) for the same key.
    func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "v",
                  let buffer = self?.current?.activeBuffer, buffer.isMarkdown else { return event }
            buffer.togglePreview()
            return nil
        }
    }
}

/// Invisible view that reports when its window becomes or stops being key.
struct KeyWindowTracker: NSViewRepresentable {
    let workspace: WorkspaceModel

    func makeNSView(context: Context) -> TrackerView {
        TrackerView(workspace: workspace)
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.workspace = workspace
    }

    final class TrackerView: NSView {
        weak var workspace: WorkspaceModel?

        init(workspace: WorkspaceModel) {
            self.workspace = workspace
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey),
                name: NSWindow.didResignKeyNotification, object: window
            )
            if window.isKeyWindow { windowDidBecomeKey() }
        }

        @objc private func windowDidBecomeKey() {
            KeyWorkspace.shared.current = workspace
        }

        @objc private func windowDidResignKey() {
            if KeyWorkspace.shared.current === workspace {
                KeyWorkspace.shared.current = nil
            }
        }
    }
}
