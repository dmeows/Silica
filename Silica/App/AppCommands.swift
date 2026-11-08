import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    /// The project in the key window. Tracked from AppKit key-window changes, since
    /// `focusedSceneValue` came back nil while the editor's NSTextView had focus.
    @ObservedObject private var keyWorkspace = KeyWorkspace.shared
    private var workspace: WorkspaceModel? { keyWorkspace.current }

    private var recents: RecentProjectsStore { .shared }
    private var settings: EditorSettings { .shared }
    private var opener: ProjectOpener { ProjectOpener(openWindow: openWindow) }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Project…") { opener.chooseAndOpen() }
                .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(recents.projects) { project in
                    Button(project.name) { opener.open(project) }
                }
                Divider()
                Button("Clear Menu") { recents.clear() }
                    .disabled(recents.projects.isEmpty)
            }

            Divider()

            Button("Quick Open…") { workspace?.toggleQuickOpen() }
                .keyboardShortcut("p")
                .disabled(workspace == nil)

            Divider()

            Button("Welcome Window") { openWindow(id: WindowID.welcome) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }

        // No printing; ⌘P is Quick Open, as in other code editors.
        CommandGroup(replacing: .printItem) {}

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

        CommandGroup(after: .sidebar) {
            Divider()

            // ⌘= also zooms in; see EditorSettings.installKeyboardShortcuts().
            Button("Increase Font Size") { settings.increaseFontSize() }
                .keyboardShortcut("+")
                .disabled(!settings.canIncreaseFontSize)

            Button("Decrease Font Size") { settings.decreaseFontSize() }
                .keyboardShortcut("-")
                .disabled(!settings.canDecreaseFontSize)

            Button("Reset Font Size") { settings.resetFontSize() }
                .keyboardShortcut("0")
                .disabled(settings.isDefaultFontSize)
        }
    }
}
