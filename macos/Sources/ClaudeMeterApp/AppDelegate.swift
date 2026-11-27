import AppKit
import SwiftUI

/// Launch behaviour of a menu bar app that must never feel like "nothing happened":
/// - opening the app (Finder, Spotlight, Launchpad, double-click while running) shows the panel in a window,
///   because the menu bar icon can be hidden (behind the notch, or by macOS menu bar settings);
/// - launching at login stays silent (menu bar only);
/// - only one instance: a second copy asks the first one to show its window and quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showNotification = Notification.Name("com.mavrizio.claudemeter.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.requested {
            Snapshot.run(model: AppModel.shared)
            return
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showNotification, object: nil, queue: .main) { _ in PanelWindow.shared.show() }

        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !atLogin { PanelWindow.shared.show() }
    }

    /// Double-click on the app while it is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelWindow.shared.show()
        return false
    }
}

enum SingleInstance {
    /// Call before anything opens the serial port. If another copy is running, wake it up and quit.
    static func enforce() {
        guard !Snapshot.requested, let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return }
        DistributedNotificationCenter.default().postNotificationName(
            AppDelegate.showNotification, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}

/// The same panel as the menu bar, in a regular window.
final class PanelWindow {
    static let shared = PanelWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = PanelView(inWindow: true).environment(AppModel.shared)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Claude Meter"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
