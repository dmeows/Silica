import Foundation
import Observation

/// A file or folder in the explorer tree. Folder contents load lazily on expand.
@Observable
final class FileNode: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool

    /// `nil` until the folder has been expanded for the first time.
    private(set) var children: [FileNode]?
    var isExpanded = false {
        didSet { if isExpanded { loadChildrenIfNeeded() } }
    }

    var id: URL { url }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }

    func loadChildrenIfNeeded() {
        guard isDirectory, children == nil else { return }
        children = Self.contents(of: url)
    }

    /// Re-reads every loaded folder, keeping existing nodes (and their expansion state).
    func reload() {
        guard isDirectory, let old = children else { return }
        let existing = Dictionary(old.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let fresh = Self.contents(of: url).map { existing[$0.url] ?? $0 }
        children = fresh
        fresh.forEach { $0.reload() }
    }

    func collapseAll() {
        children?.forEach {
            $0.isExpanded = false
            $0.collapseAll()
        }
    }

    private static let ignoredNames: Set<String> = [".DS_Store", ".git"]

    static func contents(of directory: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        return urls
            .filter { !ignoredNames.contains($0.lastPathComponent) }
            .map { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let normalized = URL(
                    filePath: url.path(percentEncoded: false),
                    directoryHint: isDir ? .isDirectory : .notDirectory
                )
                return FileNode(url: normalized, isDirectory: isDir)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
