import AppKit
import SwiftUI

/// Shared "open a folder" flow used by the welcome window and the menu bar.
struct FolderOpener {
    let openWindow: OpenWindowAction

    private var store: RecentFoldersStore { .shared }

    func chooseAndOpen() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a folder to open in GlassTextEdit"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        do {
            let folder = try store.register(url)
            openWindow(id: WindowID.workspace, value: folder.id)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func open(_ folder: RecentFolder) {
        do {
            let url = try store.resolveURL(for: folder.id)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw CocoaError(.fileNoSuchFile)
            }
            store.markOpened(folder.id)
            openWindow(id: WindowID.workspace, value: folder.id)
        } catch {
            let alert = NSAlert()
            alert.messageText = "“\(folder.name)” couldn’t be opened."
            alert.informativeText = "It may have been moved, renamed or deleted."
            alert.addButton(withTitle: "Remove from Recents")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                store.remove(folder.id)
            }
        }
    }
}

enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
    }
}
