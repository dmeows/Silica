import AppKit
import Foundation
import Observation
import SwiftUI

/// State for one open project window: the explorer tree and the open editor tabs.
@Observable
final class WorkspaceModel {
    let rootURL: URL
    let root: FileNode

    var selection: URL?
    /// The last file asked to be shown in the tree; `revealCount` changes on every
    /// request so the tree scrolls even when the same file is revealed twice.
    private(set) var revealedURL: URL?
    private(set) var revealCount = 0
    var isSidebarVisible = true
    private(set) var isQuickOpenVisible = false
    let quickOpen: QuickOpenModel
    private(set) var openTabs: [URL] = []
    private(set) var activeTab: URL?
    private(set) var buffers: [URL: EditorBuffer] = [:]

    @ObservationIgnored private var isAccessingScope: Bool
    @ObservationIgnored private var watcher: ProjectWatcher?

    var name: String { root.name }

    var activeBuffer: EditorBuffer? {
        activeTab.flatMap { buffers[$0] }
    }

    var hasUnsavedChanges: Bool {
        buffers.values.contains { $0.isDirty }
    }

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.isAccessingScope = rootURL.startAccessingSecurityScopedResource()
        self.root = FileNode(root: rootURL)
        self.quickOpen = QuickOpenModel(rootURL: rootURL)
        root.isExpanded = true
        root.loadChildrenIfNeeded()
        // Keep the tree and open files in step with changes made by other apps.
        watcher = ProjectWatcher(url: rootURL) { [weak self] in
            self?.refresh()
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        if isAccessingScope {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingScope = false
        }
    }

    // MARK: Explorer

    func handleSelectionChange() {
        guard let url = selection else { return }
        if url.hasDirectoryPath {
            if let node = node(for: url) { toggleExpansion(of: node) }
        } else {
            open(url)
        }
    }

    func toggleExpansion(of node: FileNode) {
        withAnimation(.snappy(duration: 0.2)) { node.isExpanded.toggle() }
    }

    /// Expands or collapses the selected folder; returns `false` if nothing changed.
    func setSelectedFolderExpanded(_ expanded: Bool) -> Bool {
        guard let url = selection, url.hasDirectoryPath, let node = node(for: url),
              node.isExpanded != expanded else { return false }
        toggleExpansion(of: node)
        return true
    }

    func toggleSidebar() {
        withAnimation(.snappy) { isSidebarVisible.toggle() }
    }

    // MARK: Quick Open

    func toggleQuickOpen() {
        if isQuickOpenVisible {
            hideQuickOpen()
        } else {
            quickOpen.prepareForPresentation(activeFile: activeTab)
            withAnimation(.snappy(duration: 0.18)) { isQuickOpenVisible = true }
        }
    }

    func hideQuickOpen() {
        guard isQuickOpenVisible else { return }
        withAnimation(.snappy(duration: 0.18)) { isQuickOpenVisible = false }
        // Give typing focus back to the editor.
        if let textView = activeBuffer?.textController?.textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    func openFromQuickOpen(_ url: URL) {
        hideQuickOpen()
        open(url)
        reveal(url)
    }

    /// Expands the folders above `url` so its row exists, selects it and asks the
    /// tree to scroll to it.
    func reveal(_ url: URL) {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return }
        var current = root
        for name in components.dropFirst(rootComponents.count).dropLast() {
            var next = current.children?.first { $0.name == name }
            if next == nil {
                // The folder may have appeared since the tree last read the disk.
                current.reload()
                next = current.children?.first { $0.name == name }
            }
            guard let folder = next, folder.isDirectory else { return }
            if !folder.isExpanded { folder.isExpanded = true }
            current = folder
        }
        if current.children?.contains(where: { $0.url == url }) == false {
            current.reload()
        }
        selection = url
        revealedURL = url
        revealCount += 1
    }

    /// Re-reads the tree and checks open files against the disk.
    func refresh() {
        root.reload()
        syncOpenFilesWithDisk()
    }

    private func syncOpenFilesWithDisk() {
        for url in openTabs {
            guard let buffer = buffers[url], buffer.syncWithDisk() else { continue }
            // An image or other non-text file changed: read it again.
            buffers[url] = makeBuffer(for: url)
        }
    }

    func collapseAll() {
        root.collapseAll()
    }

    func relativePath(of url: URL) -> String {
        let rootPath = rootURL.path(percentEncoded: false).trimmingTrailingSlash
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func node(for url: URL) -> FileNode? {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return nil }
        var current = root
        for name in components.dropFirst(rootComponents.count) {
            guard let next = current.children?.first(where: { $0.name == name }) else { return nil }
            current = next
        }
        return current
    }

    // MARK: Tabs

    func open(_ url: URL) {
        if buffers[url] == nil {
            buffers[url] = makeBuffer(for: url)
        }
        if !openTabs.contains(url) {
            if let active = activeTab, let index = openTabs.firstIndex(of: active) {
                openTabs.insert(url, at: index + 1)
            } else {
                openTabs.append(url)
            }
        }
        activate(url)
    }

    private func makeBuffer(for url: URL) -> EditorBuffer {
        let buffer = EditorBuffer(url: url)
        // Links in a Markdown preview open other project files here, like Quick Open.
        buffer.openFile = { [weak self] target in
            self?.open(target)
            self?.reveal(target)
        }
        return buffer
    }

    func activate(_ url: URL) {
        activeTab = url
        quickOpen.noteOpened(url)
        if selection != url {
            selection = url
        }
    }

    func closeActiveTab() {
        if let activeTab { closeTab(activeTab) }
    }

    func closeOtherTabs(than url: URL) {
        for other in openTabs where other != url {
            closeTab(other)
        }
    }

    func closeTab(_ url: URL) {
        guard let index = openTabs.firstIndex(of: url) else { return }
        if let buffer = buffers[url], buffer.isDirty, !confirmDiscardOrSave(buffer) {
            return
        }

        openTabs.remove(at: index)
        buffers[url] = nil

        if activeTab == url {
            if openTabs.isEmpty {
                activeTab = nil
                selection = nil
            } else {
                activate(openTabs[min(index, openTabs.count - 1)])
            }
        }
    }

    // MARK: Saving

    func saveActive() {
        if let buffer = activeBuffer { save(buffer) }
    }

    func saveAll() {
        for buffer in buffers.values where buffer.isDirty {
            save(buffer)
        }
    }

    @discardableResult
    private func save(_ buffer: EditorBuffer) -> Bool {
        if case .modified = buffer.diskChange(), !confirmOverwrite(buffer) {
            return false
        }
        do {
            try buffer.save()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// The file changed on disk while it had unsaved edits here. Returns `true` to
    /// write Silica's version over it.
    private func confirmOverwrite(_ buffer: EditorBuffer) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(buffer.name)” was changed by another app."
        alert.informativeText = "Saving replaces those changes with yours. Revert discards your unsaved edits and shows the file as it is on disk (you can undo it)."
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            buffer.revertToDisk()
            return false
        default:
            return false
        }
    }

    /// Returns `true` if the tab may be closed.
    private func confirmDiscardOrSave(_ buffer: EditorBuffer) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(buffer.name)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        addDontSaveButton(to: alert)
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save(buffer)
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: Closing the window

    /// Edited files, in tab order.
    var unsavedBuffers: [EditorBuffer] {
        openTabs.compactMap { buffers[$0] }.filter(\.isDirty)
    }

    /// Asks, in a sheet on `window`, whether to save edited files before the window
    /// closes or the app quits. `completion(true)` means go ahead: everything was
    /// saved, or the user chose not to save.
    func confirmClosing(in window: NSWindow, completion: @escaping (Bool) -> Void) {
        let unsaved = unsavedBuffers
        guard !unsaved.isEmpty else {
            completion(true)
            return
        }
        hideQuickOpen()

        let alert = NSAlert()
        if unsaved.count == 1 {
            alert.messageText = "Do you want to save the changes you made to “\(unsaved[0].name)”?"
            alert.informativeText = "Your changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save")
        } else {
            alert.messageText = "Do you want to save the changes you made to \(unsaved.count) files in “\(name)”?"
            let names = unsaved.prefix(5).map(\.name).formatted(.list(type: .and))
            let more = unsaved.count > 5 ? " and \(unsaved.count - 5) more" : ""
            alert.informativeText = "\(names)\(more)\n\nYour changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save All")
        }
        addDontSaveButton(to: alert)
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return completion(true) }
            switch response {
            case .alertFirstButtonReturn:
                // Stop at the first file that fails to save (or whose save is cancelled).
                let saved = unsaved.allSatisfy { !$0.isDirty || self.save($0) }
                completion(saved)
            case .alertSecondButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    private func addDontSaveButton(to alert: NSAlert) {
        let button = alert.addButton(withTitle: "Don’t Save")
        button.keyEquivalent = "d"
        button.keyEquivalentModifierMask = .command
    }
}
