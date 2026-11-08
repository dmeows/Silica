import SwiftUI

struct EditorArea: View {
    let workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            // Title bar row: tabs share it with the traffic lights.
            HStack(spacing: 8) {
                if !workspace.isSidebarVisible {
                    Color.clear.frame(width: WorkspaceLayout.trafficLightsWidth)
                    SidebarToggleButton(workspace: workspace)
                }
                EditorTabBar(workspace: workspace)
                Spacer(minLength: 0)
                if let buffer = workspace.activeBuffer, buffer.isMarkdown {
                    MarkdownModeToggle(buffer: buffer)
                        .padding(.trailing, WorkspaceLayout.cardInset + 4)
                }
            }
            .frame(height: WorkspaceLayout.titleBarHeight)

            editorCard
                .padding(.leading, workspace.isSidebarVisible ? 0 : WorkspaceLayout.cardInset)
                .padding([.trailing, .bottom], WorkspaceLayout.cardInset)
        }
        .frame(minWidth: 420)
    }

    private var editorCard: some View {
        // Corners next to the window's corners follow its radius minus the inset;
        // the others (under the tab bar) fall back to the minimum.
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(WorkspaceLayout.cardCornerRadius)))
        return Group {
            if let buffer = workspace.activeBuffer {
                BufferView(buffer: buffer)
            } else {
                EmptyEditorView(workspace: workspace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        // Liquid Glass card; a light text-background tint keeps code readable.
        .glassEffect(
            .regular,
            in: shape
        )
    }
}

// MARK: - Tabs

private struct EditorTabBar: View {
    let workspace: WorkspaceModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(workspace.openTabs, id: \.self) { url in
                        EditorTab(
                            url: url,
                            isActive: url == workspace.activeTab,
                            isDirty: workspace.buffers[url]?.isDirty == true,
                            select: { workspace.activate(url) },
                            close: { withAnimation(.snappy) { workspace.closeTab(url) } },
                            closeOthers: { withAnimation(.snappy) { workspace.closeOtherTabs(than: url) } }
                        )
                        .id(url)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: workspace.activeTab) { _, active in
                if let active {
                    withAnimation { proxy.scrollTo(active) }
                }
            }
        }
    }
}

private struct EditorTab: View {
    let url: URL
    let isActive: Bool
    let isDirty: Bool
    let select: () -> Void
    let close: () -> Void
    let closeOthers: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            FileIcon(url: url)
                .font(.caption)
            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)

            ZStack {
                if isDirty && !isHovering {
                    Circle()
                        .fill(.primary.opacity(0.7))
                        .frame(width: 7, height: 7)
                } else {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .opacity(isActive || isHovering ? 1 : 0)
                    .help("Close")
                }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .foregroundStyle(isActive ? .primary : .secondary)
        // Only the active tab sits on glass; `.identity` renders no effect.
        .glassEffect(isActive ? .regular : .identity, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close", action: close)
            Button("Close Others", action: closeOthers)
            Divider()
            Button("Show in Finder") { Finder.reveal(url) }
            Button("Copy Path") { Finder.copyPath(url) }
        }
    }
}

// MARK: - Buffer

private struct BufferView: View {
    let buffer: EditorBuffer

    var body: some View {
        switch buffer.content {
        case .text(let controller):
            if buffer.isShowingPreview, let preview = buffer.preview {
                MarkdownPreviewHost(preview: preview)
            } else {
                TextViewHost(controller: controller)
            }
        case .image(let file):
            ImagePreview(file: file)
        case .binary:
            ContentUnavailableView(
                "Binary File",
                systemImage: "doc.questionmark",
                description: Text("“\(buffer.name)” isn’t a text file, so it can’t be shown in the editor.")
            )
        case .tooLarge(let size):
            ContentUnavailableView(
                "File Too Large",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("“\(buffer.name)” is \(size.formatted(.byteCount(style: .file))), which is too large to open here.")
            )
        case .unreadable(let message):
            ContentUnavailableView(
                "Can’t Read File",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }
}

// MARK: - Markdown

/// Source / Preview switch for Markdown tabs, in the quiet icon style of the other
/// title bar buttons; the current mode is drawn in the primary color on a soft fill.
private struct MarkdownModeToggle: View {
    let buffer: EditorBuffer

    var body: some View {
        HStack(spacing: 2) {
            option("doc.plaintext", help: "Show Markdown (⇧⌘V)", isOn: !buffer.isShowingPreview) {
                buffer.setShowingPreview(false)
            }
            option("eye", help: "Show Preview (⇧⌘V)", isOn: buffer.isShowingPreview) {
                buffer.setShowingPreview(true)
            }
        }
    }

    private func option(_ symbol: String, help: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isOn ? .primary : .secondary)
        .background {
            if isOn {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(0.08))
            }
        }
        .help(help)
    }
}

// MARK: - Image

/// Shows an image file fitted to the editor card, never enlarged past one image
/// pixel per point (VS Code's and Preview's 100%), over a checkerboard so
/// transparent areas are visible.
private struct ImagePreview: View {
    let file: EditorBuffer.ImageFile

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: file.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .background(Checkerboard())
                .overlay(Rectangle().strokeBorder(.separator, lineWidth: 1))
                .frame(maxWidth: file.pixelSize.width, maxHeight: file.pixelSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(details)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var details: String {
        let size = "\(Int(file.pixelSize.width)) × \(Int(file.pixelSize.height)) px"
        return [size, file.format, file.byteCount.formatted(.byteCount(style: .file))].joined(separator: "  ·  ")
    }
}

/// Light and dark squares behind transparent pixels, as image editors draw them.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 8
            for row in 0..<Int((size.height / square).rounded(.up)) {
                for column in 0..<Int((size.width / square).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.06)))
                }
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyEditorView: View {
    let workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, height: 92)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

            VStack(spacing: 6) {
                Text(workspace.name)
                    .font(.title2.weight(.semibold))
                Text("Select a file in the sidebar to start editing.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                shortcut("Quick Open", keys: "⌘P")
                shortcut("Open Another Project", keys: "⌘O")
                shortcut("Toggle Sidebar", keys: "⌃⌘S")
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(keys)
                .monospaced()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: .capsule)
        }
    }
}
