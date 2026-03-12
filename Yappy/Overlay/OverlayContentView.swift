// Hosts the placeholder character layer tree for the fixed overlay skin.
import AppKit

@MainActor
final class OverlayContentView: NSView {
    private let hostLayer = CALayer()
    private let rig = SplitHeadCharacterRig()
    private lazy var animator = CharacterAnimator(rig: rig)
    private var currentSizeMode: OverlaySizeMode = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        hostLayer.backgroundColor = NSColor.clear.cgColor
        layer = hostLayer
        hostLayer.addSublayer(rig.rootLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        hostLayer.frame = bounds
        rig.layout(in: baseCanvasFrame())
        rig.setDisplayScale(currentSizeMode.displayScale, animated: false)
        animator.syncLayout()
    }

    func apply(state: CharacterState) {
        animator.apply(state: state)
    }

    func apply(sizeMode: OverlaySizeMode, animated: Bool) {
        currentSizeMode = sizeMode
        rig.setDisplayScale(sizeMode.displayScale, animated: animated)
    }

    func apply(speechLevel: CGFloat) {
        animator.updateSpeechLevel(speechLevel)
    }

    private func baseCanvasFrame() -> CGRect {
        CGRect(
            x: floor((bounds.width - SplitHeadCharacterRig.canvasSize.width) / 2),
            y: 0,
            width: SplitHeadCharacterRig.canvasSize.width,
            height: SplitHeadCharacterRig.canvasSize.height
        )
    }
}
