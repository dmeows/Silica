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

            List(selection: $workspace.selection) {
                if let children = workspace.root.children, !children.isEmpty {
                    ForEach(children) { node in
                        FileNodeRow(node: node, workspace: workspace)
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
            // Compact, editor-style rows.
            .environment(\.sidebarRowSize, .small)
            .environment(\.defaultMinListRowHeight, 22)
            // The sidebar list style has a fixed top inset that content margins don't
            // change. Pull the list up by most of it and clip, so rows start closer to
            // the title bar and scrolled rows still disappear at its bottom edge.
            .padding(.top, -WorkspaceLayout.sidebarListTopTrim)
            .clipped()
        }
        .onChange(of: workspace.selection) {
            workspace.handleSelectionChange()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label {
                Text(workspace.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
            }
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
    @Bindable var node: FileNode
    let workspace: WorkspaceModel

    var body: some View {
        Group {
            if node.isDirectory {
                DisclosureGroup(isExpanded: $node.isExpanded) {
                    if let children = node.children {
                        ForEach(children) { child in
                            FileNodeRow(node: child, workspace: workspace)
                        }
                    }
                } label: {
                    label
                }
                .onChange(of: node.isExpanded, initial: true) {
                    if node.isExpanded { node.loadChildrenIfNeeded() }
                }
            } else {
                label
            }
        }
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

    private var label: some View {
        HStack(spacing: 6) {
            FileIcon(url: node.url, isDirectory: node.isDirectory, isExpanded: node.isExpanded)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if workspace.buffers[node.url]?.isDirty == true {
                Circle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            }
        }
    }
}
