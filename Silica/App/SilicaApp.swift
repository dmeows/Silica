import SwiftUI

enum WindowID {
    static let welcome = "welcome"
    static let workspace = "workspace"
}

@main
struct SilicaApp: App {
    init() {
        EditorSettings.shared.installKeyboardShortcuts()
        MenuShortcutRefresh.install()
    }

    var body: some Scene {
        Window("Welcome to Silica", id: WindowID.welcome) {
            WelcomeView()
                .frame(width: 780, height: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        WindowGroup("Workspace", id: WindowID.workspace, for: RecentProject.ID.self) { $projectID in
            WorkspaceWindow(projectID: projectID)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            TextEditingCommands()
            AppCommands()
        }
    }
}
