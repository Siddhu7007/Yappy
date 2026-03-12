// Manages the floating overlay panel, including launch placement, drag persistence, and recentering.
import AppKit

enum OverlaySizeMode: Equatable {
    case idle
    case activeCover

    var displayScale: CGFloat {
        switch self {
        case .idle:
            1
        case .activeCover:
            SplitHeadCharacterRig.activeCoverScale
        }
    }
}

@MainActor
protocol OverlayPanelControlling: AnyObject {
    func show()
    func apply(state: CharacterState)
    func apply(sizeMode: OverlaySizeMode, animated: Bool)
    func apply(speechLevel: CGFloat)
    func recenter()
}

@MainActor
final class OverlayPanelController: OverlayPanelControlling {
    private let positionStore: OverlayPositionStore
    private let contentView = OverlayContentView(
        frame: CGRect(origin: .zero, size: SplitHeadCharacterRig.activeCoverCanvasSize)
    )
    private let panel: OverlayPanel
    private let anchoredBottomInset: CGFloat = 4
    private var currentSizeMode: OverlaySizeMode = .idle

    init(positionStore: OverlayPositionStore) {
        self.positionStore = positionStore
        self.panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: SplitHeadCharacterRig.activeCoverCanvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    func show() {
        panel.setFrame(resolvedFrame(), display: false)
        panel.orderFrontRegardless()
    }

    func apply(state: CharacterState) {
        panel.orderFrontRegardless()
        contentView.apply(state: state)
    }

    func apply(sizeMode: OverlaySizeMode, animated: Bool) {
        guard currentSizeMode != sizeMode else {
            return
        }

        currentSizeMode = sizeMode
        panel.orderFrontRegardless()
        contentView.apply(sizeMode: sizeMode, animated: animated)
    }

    func apply(speechLevel: CGFloat) {
        contentView.apply(speechLevel: speechLevel)
    }

    func recenter() {
        let origin = anchoredOrigin(in: primaryVisibleFrame())
        panel.setFrameOrigin(origin)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = contentView
    }

    private func resolvedFrame() -> CGRect {
        CGRect(origin: anchoredOrigin(in: primaryVisibleFrame()), size: SplitHeadCharacterRig.activeCoverCanvasSize)
    }

    private func anchoredOrigin(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - (SplitHeadCharacterRig.activeCoverCanvasSize.width / 2),
            y: visibleFrame.minY + anchoredBottomInset
        )
    }

    private func primaryVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(origin: .zero, size: SplitHeadCharacterRig.activeCoverCanvasSize)
    }
}
