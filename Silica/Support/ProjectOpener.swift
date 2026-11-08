import AppKit
import SwiftUI

/// Shared "open a project" flow used by the welcome window and the menu bar.
struct ProjectOpener {
    let openWindow: OpenWindowAction

    private var store: RecentProjectsStore { .shared }

    func chooseAndOpen() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a project folder to open in Silica"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        do {
            let project = try store.register(url)
            openWindow(id: WindowID.workspace, value: project.id)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func open(_ project: RecentProject) {
        do {
            let url = try store.resolveURL(for: project.id)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw CocoaError(.fileNoSuchFile)
            }
            store.markOpened(project.id)
            openWindow(id: WindowID.workspace, value: project.id)
        } catch {
            let alert = NSAlert()
            alert.messageText = "“\(project.name)” couldn’t be opened."
            alert.informativeText = "It may have been moved, renamed or deleted."
            alert.addButton(withTitle: "Remove from Recents")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                store.remove(project.id)
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
