import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quitting asks about unsaved files in each project window first, in a sheet,
    /// so the answer comes back later.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard UnsavedChangesGuard.GuardView.hasUnsavedChanges else { return .terminateNow }
        UnsavedChangesGuard.GuardView.confirmQuitting { proceed in
            NSApp.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}
