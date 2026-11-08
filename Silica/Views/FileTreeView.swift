import SwiftUI

struct FileTreeView: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar row: traffic lights, then the project header, then the toggle.
            HStack(spacing: 8) {
                header
                SidebarToggleButton(workspace: workspace)
            }
            .frame(height: WorkspaceLayout.titleBarHeight)
            .padding(.leading, WorkspaceLayout.trafficLightsWidth)
            .padding(.trailing, 8)
            // Above the list, which reaches up underneath this row (see below).
            .zIndex(1)

            ScrollViewReader { proxy in
                List(selection: $workspace.selection) {
                    if let children = workspace.root.children, !children.isEmpty {
                        // A flat list of the visible nodes, each indented by its depth, so the
                        // rows can draw their own compact disclosure chevrons.
                        ForEach(visibleRows(in: children), id: \.node.id) { row in
                            FileNodeRow(node: row.node, depth: row.depth, workspace: workspace)
                                .id(row.node.url)
                        }
                    } else {
                        Text("This project is empty")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                // ← / → collapse and expand folders, as the system outline did.
                .onKeyPress(.rightArrow) { workspace.setSelectedFolderExpanded(true) ? .handled : .ignored }
                .onKeyPress(.leftArrow) { workspace.setSelectedFolderExpanded(false) ? .handled : .ignored }
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
        .onChange(of: workspace.selection) {
            workspace.handleSelectionChange()
        }
    }

    private func visibleRows(in nodes: [FileNode]) -> [(node: FileNode, depth: Int)] {
        var rows: [(node: FileNode, depth: Int)] = []
        func add(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                rows.append((node, depth))
                if node.isDirectory, node.isExpanded, let children = node.children {
                    add(children, depth: depth + 1)
                }
            }
        }
        add(nodes, depth: 0)
        return rows
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(workspace.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.headline)
                .help(workspace.rootURL.path(percentEncoded: false))

            Spacer(minLength: 0)

            Button {
                workspace.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Explorer")

            Button {
                withAnimation { workspace.collapseAll() }
            } label: {
                Image(systemName: "rectangle.compress.vertical")
            }
            .help("Collapse Folders")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let workspace: WorkspaceModel

    private static let indentWidth: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            disclosureChevron
            Group {
                FileIcon(url: node.url, isDirectory: node.isDirectory, isExpanded: node.isExpanded)
                    .padding(.trailing, 2)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // Dotfiles and gitignored items fade back but stay clickable.
            .opacity(node.isDimmed ? 0.5 : 1)
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
