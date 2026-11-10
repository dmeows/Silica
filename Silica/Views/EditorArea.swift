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
                BufferView(buffer: buffer, workspace: workspace)
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

    /// The tab being dragged to a new place, and how far the pointer has carried it.
    @State private var drag: TabDrag?
    /// Each tab's laid-out width, to tell which tabs a dragged one has passed.
    @State private var tabWidths: [URL: CGFloat] = [:]

    private static let spacing: CGFloat = 6
    private static let reorderAnimation = Animation.snappy(duration: 0.2)

    var body: some View {
        let offsets = drag.flatMap(reorderLayout(for:))?.offsets ?? [:]
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Self.spacing) {
                    ForEach(workspace.openTabs, id: \.self) { url in
                        let offset = offsets[url] ?? 0
                        let isDragged = drag?.url == url
                        EditorTab(
                            url: url,
                            isActive: url == workspace.activeTab,
                            isDirty: workspace.buffers[url]?.isDirty == true,
                            isMissing: workspace.buffers[url]?.isMissingOnDisk == true,
                            select: { workspace.activate(url) },
                            close: { withAnimation(.snappy) { workspace.closeTab(url) } },
                            closeOthers: { withAnimation(.snappy) { workspace.closeOtherTabs(than: url) } },
                            drag: { handleDrag($0, of: url) }
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tabWidths[url] = $0 }
                        .offset(x: offset)
                        .zIndex(isDragged ? 1 : 0)
                        // The dragged tab stays under the pointer; the others slide out of its way.
                        .animation(isDragged ? nil : Self.reorderAnimation, value: offset)
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
            .onChange(of: workspace.openTabs) { _, tabs in
                tabWidths = tabWidths.filter { tabs.contains($0.key) }
            }
        }
    }

    private func handleDrag(_ event: TabDragEvent, of url: URL) {
        switch event {
        case .moved(let translation):
            // Dragging a tab brings it forward, as clicking it does.
            if drag?.url != url { workspace.activate(url) }
            drag = TabDrag(url: url, translation: translation)
        case .dropped(let translation):
            let destination = reorderLayout(for: TabDrag(url: url, translation: translation))?.destination
            // The new order and the end of the drag go in one animation, so every tab
            // settles from where the drag left it instead of jumping to its new place.
            withAnimation(Self.reorderAnimation) {
                if let destination { workspace.moveTab(url, to: destination) }
                drag = nil
            }
        case .cancelled:
            if drag?.url == url {
                withAnimation(Self.reorderAnimation) { drag = nil }
            }
        }
    }

    /// Where the dragged tab would land if dropped now, and how far each tab sits from
    /// its place in the row meanwhile: the dragged one follows the pointer, and the
    /// tabs it has passed step aside by its width. The order itself changes on drop.
    private func reorderLayout(for drag: TabDrag) -> (destination: Int, offsets: [URL: CGFloat])? {
        let tabs = workspace.openTabs
        guard let source = tabs.firstIndex(of: drag.url) else { return nil }
        let widths = tabs.map { tabWidths[$0] ?? 0 }
        // How far along the row a tab pushes the ones after it.
        let strides = widths.map { $0 + Self.spacing }

        // The tab stops at the ends of the row.
        let offset = min(max(drag.translation, -strides[..<source].reduce(0, +)), strides[(source + 1)...].reduce(0, +))

        // A neighbor is passed once the dragged tab's leading or trailing edge crosses its middle.
        let neighbors = offset > 0 ? Array((source + 1)..<tabs.count) : Array((0..<source).reversed())
        var destination = source
        var passed: CGFloat = 0
        for index in neighbors {
            guard abs(offset) > passed + Self.spacing + widths[index] / 2 else { break }
            passed += strides[index]
            destination = index
        }

        var offsets = [drag.url: offset]
        let slot = destination > source ? -strides[source] : strides[source]
        for index in min(source, destination)...max(source, destination) where index != source {
            offsets[tabs[index]] = slot
        }
        return (destination, offsets)
    }
}

private struct TabDrag {
    let url: URL
    /// Horizontal distance from where the drag began.
    var translation: CGFloat
}

private enum TabDragEvent {
    case moved(CGFloat)
    case dropped(CGFloat)
    /// The drag stopped without a drop.
    case cancelled
}

private struct EditorTab: View {
    let url: URL
    let isActive: Bool
    let isDirty: Bool
    /// Deleted or moved on disk since it was opened.
    let isMissing: Bool
    let select: () -> Void
    let close: () -> Void
    let closeOthers: () -> Void
    /// Reports a drag along the tab bar, which moves the tab to another place in it.
    let drag: (TabDragEvent) -> Void

    @State private var isHovering = false
    @GestureState private var isDragging = false

    var body: some View {
        HStack(spacing: 6) {
            FileIcon(url: url)
                .font(.caption)
            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .strikethrough(isMissing)
                .help(isMissing ? "Deleted from disk. Save to write it again." : "")

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
        .padding(.vertical, 6)
        .foregroundStyle(isActive ? .primary : .secondary)
        // Only the active tab sits on glass; `.identity` renders no effect.
        .glassEffect(isActive ? .regular : .identity, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: select)
        // Claiming the drag also keeps it from moving the window, which otherwise takes
        // any drag on its background. Global coordinates, as the tab moves with the drag.
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { drag(.moved($0.translation.width)) }
                .onEnded { drag(.dropped($0.translation.width)) }
        )
        // A cancelled gesture resets its state without calling `onEnded`.
        .onChange(of: isDragging) { _, isDragging in
            if !isDragging { drag(.cancelled) }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close", action: close)
            Button("Close Others", action: closeOthers)
            if !url.isUntitled {
                Divider()
                Button("Show in Finder") { Finder.reveal(url) }
                Button("Copy Path") { Finder.copyPath(url) }
            }
        }
    }
}

// MARK: - Buffer

private struct BufferView: View {
    let buffer: EditorBuffer
    let workspace: WorkspaceModel

    var body: some View {
        switch buffer.content {
        case .text(let controller):
            if buffer.isShowingPreview, let preview = buffer.preview {
                MarkdownPreviewHost(preview: preview)
            } else {
                // The status bar floats over the text's bottom corner rather than
                // taking a strip of the card, left of the minimap when it's shown.
                TextViewHost(controller: controller)
                    .overlay(alignment: .bottomTrailing) {
                        StatusBar(buffer: buffer, workspace: workspace)
                            .padding(4)
                            .padding(.trailing, EditorSettings.shared.showsMinimap ? MinimapView.width : 0)
                    }
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

// MARK: - Status bar

/// Cursor position, indentation, encoding, line endings and language, in a small
/// line over the bottom-right corner of the editor.
private struct StatusBar: View {
    let buffer: EditorBuffer
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: workspace.showGoToLine) {
                Text(position)
            }
            .buttonStyle(.plain)
            .help("Go to Line (⌘L)")
            Text(buffer.indentation.usesTabs ? "Tabs" : "Spaces: \(buffer.indentation.width)")
            Text(buffer.encodingName)
            Text(buffer.lineEndingName)
            Text(buffer.language?.displayName ?? "Plain Text")
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }

    private var position: String {
        let cursor = buffer.cursor
        let base = "Ln \(cursor.line), Col \(cursor.column)"
        return cursor.selectedLength > 0 ? base + " (\(cursor.selectedLength) selected)" : base
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
            // The app icon, as on the welcome window; it carries its own margin.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)

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
