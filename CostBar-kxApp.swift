// CostBar-kxApp.swift
import AppKit
import SwiftUI

extension Notification.Name {
    static let relayBarShowSettingsWindow = Notification.Name("relayBarShowSettingsWindow")
    static let relayBarQuit = Notification.Name("relayBarQuit")
}

@main
struct CostBar_kxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dashboardVM = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(dashboardVM)
        } label: {
            HStack(spacing: 4) {
                Text(dashboardVM.pixelMenuBarLabel)
                    .font(.system(size: 11, design: .monospaced))
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.primary)
            }
            .onAppear {
                appDelegate.configure(dashboardVM: dashboardVM)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: SettingsWindowController?
    private var allowsTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsWindow(_:)),
            name: .relayBarShowSettingsWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(quitFromMenuBar(_:)),
            name: .relayBarQuit,
            object: nil
        )
        openSettingsWindowSoon()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard allowsTermination else {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController?.hide()
                NSApp.setActivationPolicy(.accessory)
            }
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindowSoon()
        return true
    }

    func configure(dashboardVM: DashboardViewModel) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(dashboardVM: dashboardVM) { [weak self] in
                self?.hideDockIconIfNoVisibleWindows()
            }
        }
        openSettingsWindowSoon()
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        settingsWindowController?.show()
    }

    @objc func quitFromMenuBar(_ sender: Any?) {
        allowsTermination = true
        NSApp.terminate(nil)
    }

    private func openSettingsWindowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.settingsWindowController?.show()
        }
    }

    private func hideDockIconIfNoVisibleWindows() {
        let hasVisibleRegularWindow = NSApp.windows.contains {
            $0.isVisible && !($0 is NSPanel)
        }
        if !hasVisibleRegularWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void

    init(dashboardVM: DashboardViewModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let rootView = SettingsView()
            .environmentObject(dashboardVM)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "RelayBar 设置"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [onClose] in
            onClose()
        }
    }
}
