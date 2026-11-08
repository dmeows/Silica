import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false

    private var store: RecentFoldersStore { .shared }
    private var opener: FolderOpener { FolderOpener(openWindow: openWindow) }

    var body: some View {
        HStack(spacing: 0) {
            hero
                .frame(width: 330)
            recents
                .padding(.vertical, 18)
                .padding(.trailing, 18)
        }
        // Frosted, behind-window blur for the whole welcome window.
        .containerBackground(for: .window) {
            VisualEffectView(.hudWindow)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 104)
                .glassEffect(.regular.tint(.accentColor.opacity(0.85)), in: .rect(cornerRadius: 28))
                .shadow(color: .accentColor.opacity(0.35), radius: 20, y: 10)

            Text("GlassTextEdit")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 22)

            Text("Version \(Bundle.main.shortVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer(minLength: 28)

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 10) {
                    Button {
                        opener.chooseAndOpen()
                    } label: {
                        Label("Open Folder…", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("o")

                    if let last = store.folders.first {
                        Button {
                            opener.open(last)
                        } label: {
                            Label("Reopen “\(last.name)”", systemImage: "arrow.uturn.backward")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .controlSize(.extraLarge)
            }
            .frame(width: 230)

            Text("or drop a folder anywhere in this window")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)

            Spacer(minLength: 32)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Folders")
                    .font(.headline)
                Spacer()
                if !store.folders.isEmpty {
                    Button("Clear") { store.clear() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if store.folders.isEmpty {
                ContentUnavailableView(
                    "No Recent Folders",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Folders you open will show up here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.folders) { folder in
                            RecentFolderRow(folder: folder) {
                                opener.open(folder)
                            } remove: {
                                withAnimation { store.remove(folder.id) }
                            }
                        }
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                opener.open(url: isDirectory ? url : url.deletingLastPathComponent())
            }
        }
        return true
    }
}

private struct RecentFolderRow: View {
    let folder: RecentFolder
    let open: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(folder.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if isHovering {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from Recents")
                } else {
                    Text(folder.lastOpened.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open", action: open)
            Button("Show in Finder") { Finder.reveal(URL(filePath: folder.path)) }
            Button("Copy Path") { Finder.copyPath(URL(filePath: folder.path)) }
            Divider()
            Button("Remove from Recents", role: .destructive, action: remove)
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
