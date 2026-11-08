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
    var isSidebarVisible = true
    private(set) var openTabs: [URL] = []
    private(set) var activeTab: URL?
    private(set) var buffers: [URL: EditorBuffer] = [:]

    @ObservationIgnored private var isAccessingScope: Bool

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
        self.root = FileNode(url: rootURL, isDirectory: true)
        root.isExpanded = true
        root.loadChildrenIfNeeded()
    }

    func close() {
        if isAccessingScope {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingScope = false
        }
    }

    // MARK: Explorer

    func handleSelectionChange() {
        guard let url = selection else { return }
        if url.hasDirectoryPath {
            node(for: url)?.isExpanded.toggle()
        } else {
            open(url)
        }
    }

    func toggleSidebar() {
        withAnimation(.snappy) { isSidebarVisible.toggle() }
    }

    func refresh() {
        root.reload()
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
            buffers[url] = EditorBuffer(url: url)
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

    func activate(_ url: URL) {
        activeTab = url
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
        do {
            try buffer.save()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Returns `true` if the tab may be closed.
    private func confirmDiscardOrSave(_ buffer: EditorBuffer) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(buffer.name)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save(buffer)
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
}
