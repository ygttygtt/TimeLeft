import AppKit
import Combine
import SwiftUI

@main
enum TimeLeftApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = TimeLeftAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class TimeLeftAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: TimeLeftMenuBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = TimeLeftMenuBar(model: TimeLeftModel())
    }
}

@MainActor
final class TimeLeftMenuBar: NSObject, NSPopoverDelegate {
    private let model: TimeLeftModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var countdown: AnyCancellable?
    private var wantsPopover = false
    private var closingPopover = false

    init(model: TimeLeftModel) {
        self.model = model
        super.init()

        let button = item.button!
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.setAccessibilityLabel("TimeLeft")
        button.target = self
        button.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.delegate = self

        countdown = model.$countdown
            .map(\.menuTitle)
            .removeDuplicates()
            .sink { [weak button] title in
                button?.title = title ?? ""
                button?.setAccessibilityValue(title ?? "今天休息")
            }
    }

    @objc private func togglePopover() {
        wantsPopover.toggle()
        updatePopover()
    }

    private func updatePopover() {
        guard !closingPopover else { return }
        if wantsPopover, !popover.isShown {
            showPopover()
        } else if !wantsPopover, popover.isShown {
            closingPopover = true
            popover.close()
        }
    }

    private func showPopover() {
        let button = item.button!
        model.setPanelVisible(true)
        popover.appearance = NSApp.effectiveAppearance
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let controller = TimeLeftPopoverPages(model: model, animated: popover.animates) { [weak self] owner, size in
            guard let self, self.popover.isShown, !self.closingPopover,
                  self.popover.contentViewController === owner else { return }
            if self.popover.contentSize != size {
                let animates = self.popover.animates
                self.popover.animates = false
                self.popover.contentSize = size
                self.popover.animates = animates
            }
        }
        popover.contentViewController = controller
        popover.contentSize = controller.view.frame.size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        controller.view.window?.acceptsMouseMovedEvents = true
        button.highlight(true)
    }

    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.acceptsMouseMovedEvents = true
        item.button?.highlight(true)
    }

    func popoverWillClose(_ notification: Notification) {
        model.setPanelVisible(false)
        (popover.contentViewController as? TimeLeftPopoverPages)?.stopAnimation()
        if !closingPopover {
            // A system dismissal, such as clicking outside, clears the requested state.
            wantsPopover = false
            closingPopover = true
        }
    }

    func popoverDidClose(_ notification: Notification) {
        closingPopover = false
        item.button?.highlight(false)
        popover.contentViewController = nil
        Task { @MainActor [weak self] in self?.updatePopover() }
    }

}
