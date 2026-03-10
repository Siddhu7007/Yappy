// Builds the two-piece raster rig used by the overlay character.
import AppKit
import QuartzCore

@MainActor
final class SplitHeadCharacterRig {
    static let canvasSize = CGSize(width: 92, height: 92)
    static let characterSize = CGSize(width: 92, height: 92)
    static let upperHeadListeningOffset: CGFloat = 10
    static let upperHeadOpenOffset: CGFloat = 28
    static let stateAnimationDuration: CFTimeInterval = 0.10
    static let speechAnimationDuration: CFTimeInterval = 0.065

    let rootLayer = CALayer()
    let characterLayer = CALayer()
    let glowLayer = CALayer()
    let fixedBaseLayer = CALayer()
    let upperHeadLayer = CALayer()

    private let accentGlowColor = NSColor(calibratedRed: 0.34, green: 0.74, blue: 0.95, alpha: 1)
    private let errorGlowColor = NSColor.systemRed
    private var upperHeadClosedPosition = CGPoint.zero

    init() {
        configureRootLayer()
        configureCharacterLayers()
        upperHeadClosedPosition = CGPoint(x: Self.characterSize.width / 2, y: Self.characterSize.height / 2)
    }

    func layout(in bounds: CGRect) {
        rootLayer.frame = bounds
        characterLayer.frame = bounds
        fixedBaseLayer.frame = bounds
        upperHeadLayer.bounds = bounds
        upperHeadClosedPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        upperHeadLayer.position = upperHeadClosedPosition

        let glowInsetX = bounds.width * 0.2
        let glowInsetY = bounds.height * 0.26
        glowLayer.frame = bounds.insetBy(dx: glowInsetX, dy: glowInsetY)
        glowLayer.cornerRadius = glowLayer.bounds.width / 2
    }

    func applyBaseAppearance(for state: CharacterState) {
        rootLayer.opacity = state == .disabled ? 0.3 : 1
        glowLayer.backgroundColor = (state == .error ? errorGlowColor : accentGlowColor).cgColor
    }

    func resetTransforms() {
        upperHeadLayer.transform = CATransform3DIdentity
        upperHeadLayer.position = upperHeadClosedPosition
    }

    func setUpperHeadOpen(_ isOpen: Bool, animated: Bool) {
        setUpperHeadOffset(isOpen ? Self.upperHeadOpenOffset : 0, animated: animated)
    }

    func setUpperHeadListening(_ isListening: Bool, animated: Bool) {
        setUpperHeadOffset(isListening ? Self.upperHeadListeningOffset : 0, animated: animated)
    }

    func setUpperHeadOffset(_ offset: CGFloat, animated: Bool) {
        setUpperHeadOffset(offset, animated: animated, duration: Self.stateAnimationDuration)
    }

    func setUpperHeadOffset(_ offset: CGFloat, animated: Bool, duration: CFTimeInterval) {
        let targetPosition = CGPoint(
            x: upperHeadClosedPosition.x,
            y: upperHeadClosedPosition.y + offset
        )

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? duration : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        upperHeadLayer.position = targetPosition
        CATransaction.commit()
    }

    var upperHeadOpenPositionY: CGFloat {
        upperHeadClosedPosition.y + Self.upperHeadOpenOffset
    }

    var upperHeadListeningPositionY: CGFloat {
        upperHeadClosedPosition.y + Self.upperHeadListeningOffset
    }

    func speakingOffset(for normalizedLevel: CGFloat) -> CGFloat {
        let clampedLevel = max(0, min(1, normalizedLevel))
        return Self.upperHeadListeningOffset
            + ((Self.upperHeadOpenOffset - Self.upperHeadListeningOffset) * clampedLevel)
    }

    func setGlow(active: Bool, error: Bool = false, animated: Bool) {
        let targetOpacity: Float = error ? 0.28 : (active ? 0.18 : 0)

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        glowLayer.opacity = targetOpacity
        CATransaction.commit()
    }

    private func configureRootLayer() {
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = false

        characterLayer.bounds = CGRect(origin: .zero, size: Self.characterSize)
        characterLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        characterLayer.position = CGPoint(x: Self.canvasSize.width / 2, y: Self.canvasSize.height / 2)
        rootLayer.addSublayer(characterLayer)
    }

    private func configureCharacterLayers() {
        glowLayer.backgroundColor = accentGlowColor.cgColor
        glowLayer.opacity = 0
        characterLayer.addSublayer(glowLayer)

        configureImageLayer(
            fixedBaseLayer,
            named: "YappyFixedBase",
            fallbackColor: NSColor(calibratedRed: 0.38, green: 0.77, blue: 0.86, alpha: 1)
        )
        configureImageLayer(
            upperHeadLayer,
            named: "YappyUpperHead",
            fallbackColor: NSColor(calibratedRed: 0.94, green: 0.84, blue: 0.72, alpha: 1)
        )

        characterLayer.addSublayer(fixedBaseLayer)
        characterLayer.addSublayer(upperHeadLayer)
    }

    private func configureImageLayer(_ layer: CALayer, named name: String, fallbackColor: NSColor) {
        layer.bounds = CGRect(origin: .zero, size: Self.characterSize)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: Self.characterSize.width / 2, y: Self.characterSize.height / 2)
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.backgroundColor = fallbackColor.withAlphaComponent(0.2).cgColor

        if let image = NSImage(named: NSImage.Name(name)),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            layer.contents = cgImage
            layer.backgroundColor = NSColor.clear.cgColor
        }
    }
}
