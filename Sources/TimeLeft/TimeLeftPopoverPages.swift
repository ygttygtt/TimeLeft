import AppKit
import SwiftUI

@MainActor
final class TimeLeftPopoverPages: NSViewController {
    private typealias PageHost = NSHostingController<TimeLeftPanel>

    private let model: TimeLeftModel
    private let animated: Bool
    private let onResize: (TimeLeftPopoverPages, NSSize) -> Void
    private lazy var navigation = TimeLeftPanel.Navigation { [weak self] page in
        self?.show(page)
    }
    private var current: PageHost!
    private var requestedPage = TimeLeftPanel.Page.home
    private var transitioning = false
    private var animation: PageAnimation?

    init(model: TimeLeftModel, animated: Bool, onResize: @escaping (TimeLeftPopoverPages, NSSize) -> Void) {
        self.model = model
        self.animated = animated
        self.onResize = onResize
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let home = makePage(.home)
        let surface = Surface(frame: home.view.frame)
        surface.wantsLayer = true
        surface.layer?.masksToBounds = true
        view = surface
        addChild(home)
        surface.addSubview(home.view)
        current = home
    }

    private func show(_ page: TimeLeftPanel.Page) {
        requestedPage = page
        showRequestedPage()
    }

    private func showRequestedPage() {
        guard !transitioning, current.rootView.page != requestedPage else { return }
        let previous = current!
        let next = makePage(requestedPage)
        let nextSize = next.view.frame.size
        transitioning = true
        addChild(next)

        if animated {
            animate(from: previous, to: next, fitting: nextSize)
        } else {
            view.addSubview(next.view)
            didShow(next, replacing: previous, fitting: nextSize)
        }
    }

    private func animate(from previous: PageHost, to next: PageHost, fitting nextSize: NSSize) {
        let surface = view as! Surface
        surface.transitioning = true
        let direction: CGFloat = next.rootView.page.depth < previous.rootView.page.depth ? -1 : 1
        let readingDirection: CGFloat = view.userInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let distance = nextSize.width * 0.21 * direction * readingDirection
        let startHeight = view.frame.height
        next.view.setFrameOrigin(NSPoint(x: distance, y: 0))
        next.view.alphaValue = 0
        surface.addSubview(next.view)

        let animation = PageAnimation { [weak self] progress in
            guard let self else { return }
            let height = startHeight + (nextSize.height - startHeight) * progress
            self.onResize(self, NSSize(width: nextSize.width, height: height.rounded()))
            previous.view.setFrameOrigin(NSPoint(x: -distance * progress, y: 0))
            previous.view.alphaValue = 1 - progress
            next.view.setFrameOrigin(NSPoint(x: distance * (1 - progress), y: 0))
            next.view.alphaValue = progress
        } completion: { [weak self] in
            self?.didShow(next, replacing: previous, fitting: nextSize)
        }
        self.animation = animation
        animation.start()
    }

    func stopAnimation() {
        animation?.stop()
        animation = nil
    }

    private func didShow(_ next: PageHost, replacing previous: PageHost, fitting size: NSSize) {
        previous.view.removeFromSuperview()
        previous.removeFromParent()
        current = next
        next.view.frame = NSRect(origin: .zero, size: size)
        next.view.alphaValue = 1
        transitioning = false
        (view as! Surface).transitioning = false
        animation = nil
        resizeCurrentPage()
        showRequestedPage()
    }

    private func makePage(_ page: TimeLeftPanel.Page) -> PageHost {
        let host = PageHost(rootView: TimeLeftPanel(model: model, page: page, navigation: navigation) { [weak self] in
            Task { @MainActor in self?.resizeCurrentPage() }
        })
        host.sizingOptions = .intrinsicContentSize
        let size = rounded(host.view.fittingSize)
        host.view.frame = NSRect(origin: .zero, size: size)
        return host
    }

    private func resizeCurrentPage() {
        guard isViewLoaded, let current, !transitioning else { return }
        current.view.layoutSubtreeIfNeeded()
        let size = rounded(current.sizeThatFits(in: NSSize(width: TimeLeftPanel.width, height: 640)))
        current.view.frame = NSRect(origin: .zero, size: size)
        onResize(self, size)
    }

    private func rounded(_ size: NSSize) -> NSSize {
        NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private final class Surface: NSView {
        override var isFlipped: Bool { true }
        var transitioning = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            let target = super.hitTest(point)
            return transitioning && target != nil ? self : target
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let workspace = NSWorkspace.shared
            let solid = workspace.accessibilityDisplayShouldReduceTransparency
                || workspace.accessibilityDisplayShouldIncreaseContrast
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            NSColor.windowBackgroundColor.withAlphaComponent(solid ? 1 : dark ? 0.72 : 0.78).setFill()
            NSBezierPath(rect: dirtyRect).fill()
        }
    }
}

@MainActor
private final class PageAnimation: NSAnimation, NSAnimationDelegate {
    private let update: (CGFloat) -> Void
    private let completion: () -> Void

    init(update: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        self.update = update
        self.completion = completion
        super.init(duration: 0.23, animationCurve: .easeInOut)
        animationBlockingMode = .nonblocking
        frameRate = 60
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var currentProgress: NSAnimation.Progress {
        didSet { update(CGFloat(currentValue)) }
    }

    nonisolated func animationDidEnd(_ animation: NSAnimation) {
        Task { @MainActor in completion() }
    }
}
