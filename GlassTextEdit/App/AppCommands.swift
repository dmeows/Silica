import SwiftUI

extension FocusedValues {
    @Entry var workspace: WorkspaceModel?
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspace) private var workspace

    private var recents: RecentFoldersStore { .shared }
    private var opener: FolderOpener { FolderOpener(openWindow: openWindow) }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { opener.chooseAndOpen() }
                .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(recents.folders) { folder in
                    Button(folder.name) { opener.open(folder) }
                }
                Divider()
                Button("Clear Menu") { recents.clear() }
                    .disabled(recents.folders.isEmpty)
            }

            Divider()

            Button("Welcome Window") { openWindow(id: WindowID.welcome) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { workspace?.saveActive() }
                .keyboardShortcut("s")
                .disabled(workspace?.activeBuffer?.isDirty != true)

            Button("Save All") { workspace?.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(workspace?.hasUnsavedChanges != true)

            Divider()

            Button("Close Editor Tab") { workspace?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(workspace?.activeTab == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button(workspace?.isSidebarVisible == false ? "Show Sidebar" : "Hide Sidebar") {
                workspace?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(workspace == nil)

            Button("Refresh Explorer") { workspace?.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(workspace == nil)
        }
    }
}
