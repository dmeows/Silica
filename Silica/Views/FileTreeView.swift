import SwiftUI

/// The sidebar: a header on the title bar row, then the file tree or, in search
/// mode, Find in Project.
struct FileTreeView: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar row: traffic lights, then the header, then the toggle.
            HStack(spacing: 8) {
                header
                SidebarToggleButton(workspace: workspace)
            }
            .frame(height: WorkspaceLayout.titleBarHeight)
            .padding(.leading, WorkspaceLayout.trafficLightsWidth)
            .padding(.trailing, 8)
            // Above the list, which reaches up underneath this row (see below).
            .zIndex(1)

            switch workspace.sidebarMode {
            case .explorer:
                tree
                TreeFilterField(workspace: workspace)
                    .padding(8)
            case .search:
                ProjectSearchView(workspace: workspace, model: workspace.search)
            }
        }
        .onChange(of: workspace.selection) {
            workspace.handleSelectionChange()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(workspace.sidebarMode == .search ? "Search" : workspace.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.headline)
                .help(workspace.rootURL.path(percentEncoded: false))

            Spacer(minLength: 0)

            if workspace.sidebarMode == .explorer {
                Button {
                    withAnimation { workspace.collapseAll() }
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .help("Collapse Folders")
            }

            // Last, so it stays in place when the Collapse button hides in search mode.
            Button {
                if workspace.sidebarMode == .search { workspace.showExplorer() } else { workspace.showSearch() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(workspace.sidebarMode == .search ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .help(workspace.sidebarMode == .search ? "Show Explorer (⇧⌘E)" : "Find in Project (⇧⌘F)")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    // MARK: Tree

    private var tree: some View {
        ScrollViewReader { proxy in
            List(selection: $workspace.selection) {
                let rows = visibleRows()
                if rows.isEmpty {
                    Text(workspace.isFilteringTree ? "No files match “\(workspace.treeFilter)”" : "This project is empty")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                } else {
                    // A flat list of the visible nodes, each indented by its depth, so the
                    // rows can draw their own compact disclosure chevrons.
                    ForEach(rows) { row in
                        switch row.kind {
                        case .node(let node):
                            FileNodeRow(node: node, depth: row.depth, workspace: workspace)
                                .id(node.url)
                        case .draft(let folder, let isDirectory):
                            NewItemRow(folder: folder, isDirectory: isDirectory, depth: row.depth, workspace: workspace)
                                .selectionDisabled()
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            // ← / → collapse and expand folders, as the system outline did.
            .onKeyPress(.rightArrow) { workspace.setSelectedFolderExpanded(true) ? .handled : .ignored }
            .onKeyPress(.leftArrow) { workspace.setSelectedFolderExpanded(false) ? .handled : .ignored }
            // Return renames and ⌘⌫ moves to the Trash, as in Finder.
            .onKeyPress(.return) {
                guard workspace.treeEdit == nil, let selection = workspace.selection else { return .ignored }
                workspace.beginRename(selection)
                return .handled
            }
            .onKeyPress(.delete, phases: .down) { press in
                guard press.modifiers == .command, workspace.treeEdit == nil,
                      let selection = workspace.selection else { return .ignored }
                workspace.moveToTrash(selection)
                return .handled
            }
            .contextMenu {
                Button("New File…") { workspace.beginNewItem(isDirectory: false, in: workspace.rootURL) }
                Button("New Folder…") { workspace.beginNewItem(isDirectory: true, in: workspace.rootURL) }
            }
            // Compact, editor-style rows.
            .environment(\.sidebarRowSize, .small)
            .environment(\.defaultMinListRowHeight, 22)
            // The sidebar list style has a fixed top inset that content margins don't
            // change. Pull the list up by most of it and clip, so rows start closer to
            // the title bar and scrolled rows still disappear at its bottom edge.
            .padding(.top, -WorkspaceLayout.sidebarListTopTrim)
            .clipped()
            // Quick Open reveals the file it opened; wait a turn so newly
            // expanded folders have rows to scroll to.
            .onChange(of: workspace.revealCount) {
                guard let url = workspace.revealedURL else { return }
                DispatchQueue.main.async {
                    withAnimation(.snappy) { proxy.scrollTo(url, anchor: .center) }
                }
            }
        }
    }

    private struct TreeRow: Identifiable {
        enum Kind {
            case node(FileNode)
            /// The name field for a new file or folder.
            case draft(folder: URL, isDirectory: Bool)
        }

        let kind: Kind
        let depth: Int

        var id: String {
            switch kind {
            case .node(let node): node.url.absoluteString
            case .draft: "silica-new-item"
            }
        }
    }

    private func visibleRows() -> [TreeRow] {
        var rows: [TreeRow] = []
        var draftFolder: URL?
        var draftIsDirectory = false
        if case .create(let folder, let isDirectory) = workspace.treeEdit {
            draftFolder = folder
            draftIsDirectory = isDirectory
        }

        // While filtering: only matches and the folders above them, all open.
        let filtered = workspace.isFilteringTree ? workspace.treeFilterResult?.visiblePaths : nil
        if workspace.isFilteringTree && filtered == nil { return [] }

        func add(_ nodes: [FileNode], depth: Int, in folder: URL) {
            // A new item's name field goes first in its folder.
            if folder == draftFolder {
                rows.append(TreeRow(kind: .draft(folder: folder, isDirectory: draftIsDirectory), depth: depth))
            }
            for node in nodes {
                if let filtered, !filtered.contains(node.relativePath) { continue }
                rows.append(TreeRow(kind: .node(node), depth: depth))
                let isOpen = filtered != nil || node.isExpanded
                if node.isDirectory, isOpen, let children = node.children {
                    add(children, depth: depth + 1, in: node.url)
                }
            }
        }
        add(workspace.root.children ?? [], depth: 0, in: workspace.root.url)
        return rows
    }
}

// MARK: - Filter

/// The filter field under the explorer tree: shows only files whose names contain
/// the text, in their folders. ⌥⌘J focuses it; Escape clears it.
private struct TreeFilterField: View {
    @Bindable var workspace: WorkspaceModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(workspace.isFilteringTree ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            TextField("Filter", text: $workspace.treeFilter)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onKeyPress(.escape) {
                    guard !workspace.treeFilter.isEmpty else { return .ignored }
                    workspace.treeFilter = ""
                    return .handled
                }
            if let result = workspace.treeFilterResult, workspace.isFilteringTree {
                Text(result.matchCount.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(result.matchCount == 1 ? "1 matching file" : "\(result.matchCount.formatted()) matching files")
            }
            if !workspace.treeFilter.isEmpty {
                Button {
                    workspace.treeFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Filter")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .onChange(of: workspace.treeFilterFocusRequest) { isFocused = true }
    }
}

// MARK: - Rows

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let workspace: WorkspaceModel

    private static let indentWidth: CGFloat = 14

    private var isRenaming: Bool {
        workspace.treeEdit == .rename(node.url)
    }

    /// Drawn open: expanded, or shown with its matches while filtering.
    private var isOpen: Bool {
        node.isExpanded || workspace.isFilteringTree
    }

    /// The name, with the filter text in bold on a soft accent background.
    private var highlightedName: AttributedString {
        var name = AttributedString(node.name)
        guard workspace.isFilteringTree,
              let range = TreeFilter.matchRange(of: workspace.treeFilter.trimmingCharacters(in: .whitespaces), in: node.name),
              let lower = AttributedString.Index(range.lowerBound, within: name),
              let upper = AttributedString.Index(range.upperBound, within: name) else { return name }
        name[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        name[lower..<upper].backgroundColor = Color.accentColor.opacity(0.25)
        return name
    }

    var body: some View {
        HStack(spacing: 4) {
            disclosureChevron
            Group {
                FileIcon(url: node.url, isDirectory: node.isDirectory, isExpanded: isOpen)
                    .padding(.trailing, 2)
                if isRenaming {
                    NameField(initialName: node.name, selectsExtension: node.isDirectory) { name in
                        if let name { workspace.rename(node.url, to: name) } else { workspace.cancelTreeEdit() }
                    }
                } else {
                    Text(highlightedName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            // Dotfiles and gitignored items fade back but stay clickable.
            .opacity(node.isDimmed && !isRenaming ? 0.5 : 1)
            Spacer(minLength: 0)
            if workspace.buffers[node.url]?.isDirty == true {
                Circle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            }
        }
        .padding(.leading, CGFloat(depth) * Self.indentWidth)
        .tag(node.url)
        .contextMenu {
            if !node.isDirectory {
                Button("Open") { workspace.open(node.url) }
                Divider()
            }
            let folder = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
            Button("New File…") { workspace.beginNewItem(isDirectory: false, in: folder) }
            Button("New Folder…") { workspace.beginNewItem(isDirectory: true, in: folder) }
            Divider()
            Button("Rename…") { workspace.beginRename(node.url) }
            Button("Duplicate") { workspace.duplicate(node.url) }
            Button("Move to Trash") { workspace.moveToTrash(node.url) }
            Divider()
            Button("Show in Finder") { Finder.reveal(node.url) }
            Button("Copy Path") { Finder.copyPath(node.url) }
            Button("Copy Relative Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(workspace.relativePath(of: node.url), forType: .string)
            }
        }
    }

    /// A smaller chevron than the system outline's; files get the same width of space.
    @ViewBuilder
    private var disclosureChevron: some View {
        if node.isDirectory {
            // A button, so the click toggles the folder without also selecting the row
            // (selecting a folder row toggles it too).
            Button {
                workspace.toggleExpansion(of: node)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 12, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The filter decides what's shown while it's on.
            .disabled(workspace.isFilteringTree)
        } else {
            Color.clear.frame(width: 12, height: 16)
        }
    }
}

/// The row where a new file or folder gets its name.
private struct NewItemRow: View {
    let folder: URL
    let isDirectory: Bool
    let depth: Int
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 12, height: 16)
            FileIcon(url: folder.appending(path: "untitled"), isDirectory: isDirectory)
                .padding(.trailing, 2)
            NameField(initialName: "", selectsExtension: true) { name in
                if let name {
                    workspace.createItem(named: name, in: folder, isDirectory: isDirectory)
                } else {
                    workspace.cancelTreeEdit()
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
    }
}

/// An inline name field: Return or clicking away commits, Escape cancels
/// (`onFinish(nil)`). Renaming a file selects the name without its extension.
private struct NameField: View {
    let initialName: String
    let selectsExtension: Bool
    let onFinish: (String?) -> Void

    @State private var name = ""
    @State private var selection: TextSelection?
    @State private var isFinished = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $name, selection: $selection)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { finish(name) }
            .onKeyPress(.escape) {
                finish(nil)
                return .handled
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    selectStem()
                } else {
                    finish(name.isEmpty ? nil : name)
                }
            }
            .onAppear {
                name = initialName
                // After the row is in the list, or the focus doesn't take; once more a
                // moment later in case the list was still laying out (e.g. just after launch).
                DispatchQueue.main.async { isFocused = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !isFocused && !isFinished { isFocused = true }
                }
            }
    }

    /// Selects the name, without the extension when renaming a file. Done once focus
    /// lands, since focusing a field selects all of it.
    private func selectStem() {
        DispatchQueue.main.async {
            let stemEnd = selectsExtension
                ? name.endIndex
                : (name.lastIndex(of: ".").flatMap { $0 == name.startIndex ? nil : $0 } ?? name.endIndex)
            selection = TextSelection(range: name.startIndex..<stemEnd)
        }
    }

    private func finish(_ result: String?) {
        guard !isFinished else { return }
        isFinished = true
        onFinish(result)
    }
}
