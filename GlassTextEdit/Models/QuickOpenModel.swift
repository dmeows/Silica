import Foundation
import Observation

/// One row in the Quick Open list.
struct QuickOpenResult: Identifiable {
    let item: QuickOpenItem
    /// Matched scalar indices into `item.path`, for highlighting.
    let positions: [Int]
    let isRecent: Bool

    var id: URL { item.url }
}

/// State behind Quick Open (⌘P): a background-built index of the project's files,
/// the query, the ranked results and the keyboard selection.
@Observable
final class QuickOpenModel {
    static let resultLimit = 60

    let rootURL: URL

    var query = "" {
        didSet { updateResults() }
    }
    private(set) var results: [QuickOpenResult] = []
    var selectedIndex = 0
    private(set) var isIndexing = false

    @ObservationIgnored private var items: [QuickOpenItem] = []
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    /// Most recently opened files first.
    @ObservationIgnored private(set) var recentFiles: [URL] = []

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    var selectedResult: QuickOpenResult? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    /// Clears the query and rescans the project; the previous index is shown meanwhile.
    func prepareForPresentation(activeFile: URL?) {
        query = ""
        reindex(activeFile: activeFile)
        updateResults(activeFile: activeFile)
    }

    func noteOpened(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 30 { recentFiles.removeLast() }
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + results.count) % results.count
    }

    // MARK: Results

    @ObservationIgnored private var activeFile: URL?

    private func updateResults(activeFile: URL? = nil) {
        if let activeFile { self.activeFile = activeFile }
        let query = FuzzyMatcher.prepare(query)

        if query.isEmpty {
            results = defaultResults()
        } else {
            var matches: [(QuickOpenItem, FuzzyMatch)] = []
            for item in items {
                if let match = FuzzyMatcher.match(query, in: item) {
                    matches.append((item, match))
                }
            }
            matches.sort { lhs, rhs in
                if lhs.1.score != rhs.1.score { return lhs.1.score > rhs.1.score }
                if lhs.0.path.count != rhs.0.path.count { return lhs.0.path.count < rhs.0.path.count }
                return lhs.0.path < rhs.0.path
            }
            results = matches.prefix(Self.resultLimit).map {
                QuickOpenResult(item: $0.0, positions: $0.1.positions, isRecent: false)
            }
        }
        selectedIndex = 0
    }

    /// With no query: recently opened files (except the current one), then the rest by path.
    private func defaultResults() -> [QuickOpenResult] {
        let byURL = Dictionary(items.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentFiles
            .filter { $0 != activeFile }
            .compactMap { byURL[$0] }
        let recentSet = Set(recent.map(\.url))
        let rest = items.lazy.filter { !recentSet.contains($0.url) && $0.url != self.activeFile }
        return (recent.map { QuickOpenResult(item: $0, positions: [], isRecent: true) }
            + rest.prefix(Self.resultLimit).map { QuickOpenResult(item: $0, positions: [], isRecent: false) })
            .prefix(Self.resultLimit)
            .map { $0 }
    }

    // MARK: Index

    private func reindex(activeFile: URL?) {
        indexTask?.cancel()
        isIndexing = true
        let root = rootURL
        indexTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                ProjectFileIndex.scan(root: root)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.items = items
            self.isIndexing = false
            let selected = self.selectedResult?.id
            self.updateResults()
            // Keep the highlighted row if it is still there after the refresh.
            if let selected, let index = self.results.firstIndex(where: { $0.id == selected }) {
                self.selectedIndex = index
            }
        }
    }
}

/// Lists a project's files for Quick Open.
nonisolated enum ProjectFileIndex {
    static let maxFiles = 50_000

    /// Folders that are version-control metadata, dependencies or build output.
    static let skippedFolders: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", ".build", ".swiftpm", "DerivedData", "Pods",
    ]

    static func scan(root: URL) -> [QuickOpenItem] {
        let rootPath = root.path(percentEncoded: false).trimmingTrailingSlash
        guard let enumerator = FileManager().enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var items: [QuickOpenItem] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { return [] }
            let name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedFolders.contains(name) { enumerator.skipDescendants() }
                continue
            }
            if name == ".DS_Store" { continue }

            let path = url.path(percentEncoded: false)
            guard path.hasPrefix(rootPath + "/") else { continue }
            // Same form as the explorer tree's URLs, so tabs aren't opened twice.
            let normalized = URL(filePath: path, directoryHint: .notDirectory)
            items.append(QuickOpenItem(url: normalized, path: String(path.dropFirst(rootPath.count + 1))))
            if items.count >= maxFiles { break }
        }
        items.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return items
    }
}
