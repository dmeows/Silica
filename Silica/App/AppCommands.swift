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
            Button("New File") { workspace?.beginNewItem(isDirectory: false) }
                .keyboardShortcut("n")
                .disabled(workspace == nil)

            Button("New Folder") { workspace?.beginNewItem(isDirectory: true) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(workspace == nil)

            Divider()

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

            Button("Save As…") { workspace?.saveActiveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(workspace?.activeBuffer?.textController == nil)

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

            // ⇧⌘E, ⇧⌘F and ⇧⌘S are also handled by KeyWorkspace.installKeyboardShortcuts().
            Button("Explorer") { workspace?.showExplorer() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Button("Find in Project") { workspace?.showSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Button("Refresh Explorer") { workspace?.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Divider()

            // ⇧⌘V itself is handled by KeyWorkspace.installKeyboardShortcuts().
            Button(workspace?.activeBuffer?.isShowingPreview == true ? "Show Markdown" : "Show Preview") {
                workspace?.activeBuffer?.togglePreview()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(workspace?.activeBuffer?.isMarkdown != true)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Toggle("Word Wrap", isOn: Binding(
                get: { settings.wrapsLines },
                set: { settings.wrapsLines = $0 }
            ))
            .keyboardShortcut("z", modifiers: .option)

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

        CommandMenu("Editor") {
            let hasText = workspace?.activeBuffer?.textController != nil

            Button("Go to Line…") { workspace?.showGoToLine() }
                .keyboardShortcut("l")
                .disabled(!hasText)

            Divider()

            editorAction("Toggle Comment", #selector(EditorTextView.toggleComment(_:)), key: "/", modifiers: .command)
            editorAction("Indent", #selector(EditorTextView.indentLines(_:)), key: "]", modifiers: .command)
            editorAction("Outdent", #selector(EditorTextView.outdentLines(_:)), key: "[", modifiers: .command)

            Divider()

            editorAction("Move Line Up", #selector(EditorTextView.moveLinesUp(_:)), key: .upArrow, modifiers: .option)
            editorAction("Move Line Down", #selector(EditorTextView.moveLinesDown(_:)), key: .downArrow, modifiers: .option)
            editorAction("Duplicate Line Up", #selector(EditorTextView.duplicateLinesUp(_:)), key: .upArrow, modifiers: [.option, .shift])
            editorAction("Duplicate Line Down", #selector(EditorTextView.duplicateLinesDown(_:)), key: .downArrow, modifiers: [.option, .shift])
        }
    }

    /// A menu item that sends `action` to the focused editor through the responder chain.
    private func editorAction(_ title: String, _ action: Selector, key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        Button(title) { NSApp.sendAction(action, to: nil, from: nil) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(workspace?.activeBuffer?.textController == nil)
    }
}
