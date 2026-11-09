import SwiftUI

enum WindowID {
    static let welcome = "welcome"
    static let workspace = "workspace"
}

@main
struct SilicaApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        EditorSettings.shared.installKeyboardShortcuts()
        MenuShortcutRefresh.install()
        KeyWorkspace.shared.installKeyboardShortcuts()
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
        // Files and folders from Finder go to AppDelegate/ExternalOpener; without
        // this, SwiftUI also brings up this window for each of them.
        .handlesExternalEvents(matching: [])

        WindowGroup("Workspace", id: WindowID.workspace, for: RecentProject.ID.self) { $projectID in
            WorkspaceWindow(projectID: projectID)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .handlesExternalEvents(matching: [])
        .commands {
            TextEditingCommands()
            AppCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
