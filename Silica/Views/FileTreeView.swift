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

            Button {
                if workspace.sidebarMode == .search { workspace.showExplorer() } else { workspace.showSearch() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(workspace.sidebarMode == .search ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .help(workspace.sidebarMode == .search ? "Show Explorer (⇧⌘E)" : "Find in Project (⇧⌘F)")

            if workspace.sidebarMode == .explorer {
                Button {
                    withAnimation { workspace.collapseAll() }
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .help("Collapse Folders")
            }
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
                    Text("This project is empty")
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

        func add(_ nodes: [FileNode], depth: Int, in folder: URL) {
            // A new item's name field goes first in its folder.
            if folder == draftFolder {
                rows.append(TreeRow(kind: .draft(folder: folder, isDirectory: draftIsDirectory), depth: depth))
            }
            for node in nodes {
                rows.append(TreeRow(kind: .node(node), depth: depth))
                if node.isDirectory, node.isExpanded, let children = node.children {
                    add(children, depth: depth + 1, in: node.url)
                }
            }
        }
        add(workspace.root.children ?? [], depth: 0, in: workspace.root.url)
        return rows
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

    var body: some View {
        HStack(spacing: 4) {
            disclosureChevron
            Group {
                FileIcon(url: node.url, isDirectory: node.isDirectory, isExpanded: node.isExpanded)
                    .padding(.trailing, 2)
                if isRenaming {
                    NameField(initialName: node.name, selectsExtension: node.isDirectory) { name in
                        if let name { workspace.rename(node.url, to: name) } else { workspace.cancelTreeEdit() }
                    }
                } else {
                    Text(node.name)
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
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .frame(width: 12, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
