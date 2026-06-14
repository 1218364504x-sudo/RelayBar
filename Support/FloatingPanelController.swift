import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private weak var dashboardVM: DashboardViewModel?

    init(dashboardVM: DashboardViewModel) {
        self.dashboardVM = dashboardVM
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 220),
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "RelayBar Floating"
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self

        let rootView = FloatingBalanceView()
            .environmentObject(dashboardVM)
        panel.contentView = NSHostingView(rootView: rootView)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }
}
