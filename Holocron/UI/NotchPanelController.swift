import AppKit
import SwiftUI

/// Hosts the notch UI in a borderless, non-activating NSPanel that floats
/// above the menu bar and never steals focus from the terminal/editor.
@MainActor
final class NotchPanelController: NSObject {
    enum Mode {
        case compact
        case expanded
    }

    private(set) var mode: Mode = .compact
    private var panel: NSPanel!
    private var hostingView: NSHostingView<NotchRootView>!
    private let state: AppState
    private var collapseWorkItem: DispatchWorkItem?
    /// Expanded because of a card or hotkey: don't collapse on mouse exit.
    private var pinnedOpen = false

    static let compactFallbackSize = NSSize(width: 240, height: 34)
    static let expandedSize = NSSize(width: 460, height: 540)

    init(state: AppState) {
        self.state = state
        super.init()

        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: Self.compactFallbackSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel

        let root = NotchRootView(
            state: state,
            onHoverChange: { [weak self] hovering in self?.hoverChanged(hovering) },
            onTogglePin: { [weak self] in self?.toggle() }
        )
        hostingView = NSHostingView(rootView: root)
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        applyFrame(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if mode == .compact {
            setMode(.expanded, pinned: true)
        } else {
            setMode(.compact, pinned: false)
        }
    }

    /// A card appeared: force the panel open.
    func presentAttention() {
        if !panel.isVisible { show() }
        setMode(.expanded, pinned: true)
    }

    /// Cards resolved: allow collapse (unless the pointer is inside).
    func releaseAttention() {
        pinnedOpen = false
        scheduleCollapse(after: 0.8)
    }

    private func hoverChanged(_ hovering: Bool) {
        if hovering {
            collapseWorkItem?.cancel()
            if mode == .compact { setMode(.expanded, pinned: false) }
        } else if !pinnedOpen {
            scheduleCollapse(after: 0.35)
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pinnedOpen else { return }
            self.setMode(.compact, pinned: false)
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setMode(_ newMode: Mode, pinned: Bool) {
        pinnedOpen = pinned && newMode == .expanded
        guard mode != newMode else { return }
        mode = newMode
        state.panelExpanded = newMode == .expanded
        applyFrame(animated: true)
    }

    @objc private func screensChanged() {
        applyFrame(animated: false)
    }

    // MARK: - Geometry

    /// Prefer the built-in display with a notch; otherwise the main screen.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func applyFrame(animated: Bool) {
        guard let screen = targetScreen else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        state.screenHasNotch = hasNotch

        let compactSize: NSSize
        if hasNotch {
            // Wings on both sides of the hardware notch carry the indicators;
            // the middle of the pill is hidden behind the notch itself.
            let notchWidth = notchWidth(of: screen) ?? 200
            compactSize = NSSize(width: notchWidth + 120, height: screen.safeAreaInsets.top + 6)
        } else {
            compactSize = Self.compactFallbackSize
        }
        state.compactSize = compactSize

        let size = mode == .compact ? compactSize : Self.expandedSize
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        let frame = NSRect(origin: origin, size: size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Physical notch width, derived from the auxiliary top areas Apple
    /// exposes on notched screens.
    private func notchWidth(of screen: NSScreen) -> CGFloat? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let width = screen.frame.width - left.width - right.width
        return width > 40 ? width : nil
    }
}

/// Panel subclass: never becomes key/main, so focus stays in the terminal.
/// Buttons still receive clicks (mouse events don't require key status).
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit normally pushes borderless windows below the menu bar. The
    /// whole point of this panel is to hug the top edge of the screen (and
    /// blend into the notch), so the frame is returned untouched.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
