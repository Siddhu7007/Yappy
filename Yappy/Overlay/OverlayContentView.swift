// Hosts the placeholder character layer tree for the fixed overlay skin.
import AppKit

@MainActor
final class OverlayContentView: NSView {
    private let hostLayer = CALayer()
    private let rig = SplitHeadCharacterRig()
    private lazy var animator = CharacterAnimator(rig: rig)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        rig.layout(in: bounds)
    }

    func apply(state: CharacterState) {
        animator.apply(state: state)
    }

    func apply(speechLevel: CGFloat) {
        animator.updateSpeechLevel(speechLevel)
    }
}
