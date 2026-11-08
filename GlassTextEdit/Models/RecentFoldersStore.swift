import Foundation
import Observation

struct RecentFolder: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var path: String
    var bookmark: Data
    var lastOpened: Date

    /// Path with the user's real home directory abbreviated to `~`.
    var displayPath: String {
        let home = RealHome.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

enum RecentFolderError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "This folder is no longer in the recent folders list."
    }
}

/// Persists the folders the user has opened as security-scoped bookmarks,
/// so the sandboxed app can reopen them across launches.
@Observable
final class RecentFoldersStore {
    static let shared = RecentFoldersStore()

    private(set) var folders: [RecentFolder] = []

    private let defaultsKey = "RecentFolders"
    private let maxCount = 15

    private init() {
        load()
    }

    func folder(withID id: RecentFolder.ID) -> RecentFolder? {
        folders.first { $0.id == id }
    }

    /// Adds (or bumps) a folder the user just granted access to.
    @discardableResult
    func register(_ url: URL) throws -> RecentFolder {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let path = url.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash

        var entry: RecentFolder
        if let index = folders.firstIndex(where: { $0.path == path }) {
            entry = folders.remove(at: index)
            entry.bookmark = bookmark
            entry.name = url.lastPathComponent
            entry.lastOpened = .now
        } else {
            entry = RecentFolder(id: UUID(), name: url.lastPathComponent, path: path, bookmark: bookmark, lastOpened: .now)
        }
        folders.insert(entry, at: 0)
        if folders.count > maxCount {
            folders.removeLast(folders.count - maxCount)
        }
        save()
        return entry
    }

    func markOpened(_ id: RecentFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        var entry = folders.remove(at: index)
        entry.lastOpened = .now
        folders.insert(entry, at: 0)
        save()
    }

    func remove(_ id: RecentFolder.ID) {
        folders.removeAll { $0.id == id }
        save()
    }

    func clear() {
        folders.removeAll()
        save()
    }

    /// Resolves the bookmark to a URL. The caller is responsible for
    /// starting/stopping security-scoped access.
    func resolveURL(for id: RecentFolder.ID) throws -> URL {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw RecentFolderError.notFound
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: folders[index].bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                folders[index].bookmark = fresh
                folders[index].path = url.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash
                folders[index].name = url.lastPathComponent
                save()
            }
        }
        return url
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentFolder].self, from: data)
        else { return }
        folders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum RealHome {
    /// The user's home directory (not the sandbox container).
    static let path: String = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }()
}

extension String {
    var trimmingTrailingSlash: String {
        count > 1 && hasSuffix("/") ? String(dropLast()) : self
    }
}
