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
    /// Expanded because of a card or hotkey: don't collapse on mouse exit.
    private var pinnedOpen = false
    /// While expanded (and not pinned), a timer polls the real pointer
    /// position to decide when to collapse. Hover events only ever OPEN the
    /// panel (exit events misfire while the window resizes).
    private var pointerWatchTimer: Timer?
    private var pointerOutsideTicks = 0

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
            onTogglePin: { [weak self] in self?.toggle() }
        )
        hostingView = NSHostingView(rootView: root)
        // CRITICAL: by default NSHostingView installs Auto Layout constraints
        // that drive the WINDOW's size from the SwiftUI content size. They
        // fight our setFrame() calls and leave the panel detached below the
        // screen top while the content springs. The window frame is ours.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        // Hover-to-expand via an AppKit tracking area: deterministic, unlike
        // SwiftUI onHover in a borderless panel that gets resized.
        // .inVisibleRect keeps it in sync with every window resize.
        // .mouseMoved matters: entering the window outside the pill must not
        // expand, but sliding from there onto the pill must — and no new
        // mouseEntered fires in that case.
        hostingView.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        panel.acceptsMouseMovedEvents = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        applyFrame()
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

    /// Cards resolved: allow collapse again (the pointer watcher takes over).
    func releaseAttention() {
        pinnedOpen = false
        updatePointerWatch()
    }

    // Explicit selector names: NSTrackingArea sends `mouseEntered:` /
    // `mouseExited:` / `mouseMoved:` to its owner, but Swift would export
    // these methods as `mouseEnteredWith:` etc. — never delivered.
    @objc(mouseEntered:)
    func mouseEntered(with event: NSEvent) {
        expandIfPointerOnPill()
    }

    @objc(mouseMoved:)
    func mouseMoved(with event: NSEvent) {
        expandIfPointerOnPill()
    }

    @objc(mouseExited:)
    func mouseExited(with event: NSEvent) {
        // Ignored on purpose: exit events misfire during resizes. The
        // pointer watcher decides when to collapse.
    }

    /// The window can transiently be LARGER than the visible pill (it keeps
    /// the expanded size for 0.45s while the collapse animation plays), so
    /// hovering the emptied area must not re-open the panel: only the pill
    /// rectangle itself is a hover target.
    private func expandIfPointerOnPill() {
        guard mode == .compact else { return }
        let size = state.compactSize
        let frame = panel.frame
        let pillRect = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if pillRect.contains(NSEvent.mouseLocation) {
            setMode(.expanded, pinned: false)
        }
    }

    private func setMode(_ newMode: Mode, pinned: Bool) {
        pinnedOpen = pinned && newMode == .expanded
        if mode != newMode {
            mode = newMode
            if newMode == .expanded {
                // Grow the window FIRST (visually a no-op: the content still
                // draws the pill), then start the spring on the next runloop
                // tick so it plays inside a stable window. Resizing and
                // animating in the same pass stutters.
                applyFrame()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.mode == .expanded else { return }
                    self.state.panelExpanded = true
                }
            } else {
                // Collapse: spring now, shrink the window after it played.
                state.panelExpanded = false
                applyFrame(afterCollapseAnimation: true)
            }
        }
        updatePointerWatch()
    }

    // MARK: - Pointer watcher (collapse decision)

    private func updatePointerWatch() {
        let shouldWatch = mode == .expanded && !pinnedOpen
        if shouldWatch {
            guard pointerWatchTimer == nil else { return }
            pointerOutsideTicks = 0
            pointerWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                Task { @MainActor [weak self] in self?.pointerTick() }
            }
        } else {
            pointerWatchTimer?.invalidate()
            pointerWatchTimer = nil
        }
    }

    private func pointerTick() {
        guard mode == .expanded, !pinnedOpen else {
            updatePointerWatch()
            return
        }
        // NSEvent.mouseLocation and panel.frame share screen coordinates.
        let zone = panel.frame.insetBy(dx: -12, dy: -12)
        if zone.contains(NSEvent.mouseLocation) {
            pointerOutsideTicks = 0
        } else {
            pointerOutsideTicks += 1
            if pointerOutsideTicks >= 2 {
                setMode(.compact, pinned: false)
            }
        }
    }

    @objc private func screensChanged() {
        applyFrame()
    }

    // MARK: - Geometry

    /// Prefer the built-in display with a notch; otherwise the main screen.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func applyFrame(afterCollapseAnimation: Bool = false) {
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
        let frame = NSRect(
            origin: NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height
            ),
            size: size
        )

        if afterCollapseAnimation {
            // Keep the large window while the SwiftUI collapse spring plays,
            // then shrink so the invisible area stops swallowing clicks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.mode == .compact else { return }
                self.panel.setFrame(frame, display: true)
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
