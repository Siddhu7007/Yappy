// Builds the two-piece raster rig used by the overlay character.
import AppKit
import QuartzCore

@MainActor
final class SplitHeadCharacterRig {
    enum UpperHeadHingeAlignment: Equatable {
        case centered
        case left
        case right

        var anchorPoint: CGPoint {
            switch self {
            case .centered:
                SplitHeadCharacterRig.upperHeadCenterAnchorPoint
            case .left:
                SplitHeadCharacterRig.upperHeadLeftHingeAnchorPoint
            case .right:
                SplitHeadCharacterRig.upperHeadRightHingeAnchorPoint
            }
        }
    }

    nonisolated static let canvasSize = CGSize(width: 92, height: 92)
    nonisolated static let characterSize = CGSize(width: 92, height: 92)
    nonisolated static let upperHeadCenterAnchorPoint = CGPoint(x: 0.5, y: 0.623)
    nonisolated static let upperHeadLeftHingeAnchorPoint = CGPoint(x: 0.23, y: 0.623)
    nonisolated static let upperHeadRightHingeAnchorPoint = CGPoint(x: 0.753, y: 0.623)
    nonisolated static let activeCoverScale: CGFloat = 2.0
    nonisolated static let upperHeadListeningOffset: CGFloat = 5
    nonisolated static let upperHeadOpenOffset: CGFloat = 28
    nonisolated static let stateAnimationDuration: CFTimeInterval = 0.10
    nonisolated static let speechAnimationDuration: CFTimeInterval = 0.09
    nonisolated static let speakingCadenceBeatDuration: CFTimeInterval = 0.14
    nonisolated static let speakingCadenceCenterOffset: CGFloat = 18
    nonisolated static let speakingCadenceSideOffset: CGFloat = 11
    nonisolated static let speakingCadenceTiltDegrees: CGFloat = 8
    nonisolated static let speakingCadenceHorizontalOffset: CGFloat = 2
    nonisolated static let activeCoverTopPadding: CGFloat = speakingCadenceCenterOffset + 4
    nonisolated static let blinkDuration: CFTimeInterval = 0.16
    nonisolated static var activeCoverCanvasSize: CGSize {
        CGSize(
            width: canvasSize.width * activeCoverScale,
            height: (canvasSize.height + activeCoverTopPadding) * activeCoverScale
        )
    }
    nonisolated static let expandScaleAnimationDuration: CFTimeInterval = 0.085
    nonisolated static let collapseScaleAnimationDuration: CFTimeInterval = 0.12

    let rootLayer = CALayer()
    let characterLayer = CALayer()
    let fixedBaseLayer = CALayer()
    let upperHeadLayer = CALayer()
    let leftEyeBlinkCoverLayer = CALayer()
    let rightEyeBlinkCoverLayer = CALayer()
    let leftEyeClosedLineLayer = CALayer()
    let rightEyeClosedLineLayer = CALayer()

    private let accentGlowColor = NSColor(calibratedRed: 0.34, green: 0.74, blue: 0.95, alpha: 1)
    private let errorGlowColor = NSColor.systemRed
    private let upperHeadColor = NSColor(calibratedRed: 0.94, green: 0.84, blue: 0.72, alpha: 1)
    private var upperHeadClosedPosition = CGPoint.zero
    private(set) var displayScale: CGFloat = 1
    private(set) var upperHeadTiltDegrees: CGFloat = 0
    private(set) var upperHeadOffset: CGFloat = 0
    private(set) var upperHeadHorizontalOffset: CGFloat = 0
    private(set) var upperHeadHingeAlignment: UpperHeadHingeAlignment = .centered

    init() {
        configureRootLayer()
        configureCharacterLayers()
        upperHeadClosedPosition = Self.closedUpperHeadPosition(
            in: CGRect(origin: .zero, size: Self.characterSize),
            hingeAlignment: .centered
        )
        upperHeadLayer.position = upperHeadClosedPosition
    }

    func layout(in frame: CGRect) {
        let localBounds = CGRect(origin: .zero, size: frame.size)

        rootLayer.bounds = localBounds
        rootLayer.position = CGPoint(x: frame.midX, y: frame.minY)
        characterLayer.frame = localBounds
        fixedBaseLayer.frame = localBounds
        upperHeadLayer.bounds = localBounds
        upperHeadClosedPosition = Self.closedUpperHeadPosition(in: localBounds, hingeAlignment: upperHeadHingeAlignment)
        upperHeadLayer.position = upperHeadClosedPosition
        layoutEyeLayers(in: localBounds)

        let glowInsetX = localBounds.width * 0.16
        let glowInsetY = localBounds.height * 0.18
        let glowBounds = localBounds.insetBy(dx: glowInsetX, dy: glowInsetY)
        characterLayer.shadowPath = CGPath(ellipseIn: glowBounds, transform: nil)
    }

    func applyBaseAppearance(for state: CharacterState) {
        rootLayer.opacity = state == .disabled ? 0.3 : 1
        characterLayer.shadowColor = (state == .error ? errorGlowColor : accentGlowColor).cgColor
    }

    func resetTransforms() {
        upperHeadTiltDegrees = 0
        upperHeadOffset = 0
        upperHeadHorizontalOffset = 0
        upperHeadHingeAlignment = .centered
        upperHeadClosedPosition = Self.closedUpperHeadPosition(in: upperHeadLayer.bounds, hingeAlignment: .centered)
        upperHeadLayer.anchorPoint = upperHeadHingeAlignment.anchorPoint
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
        setUpperHeadPose(
            offset: offset,
            tiltDegrees: 0,
            horizontalOffset: 0,
            hingeAlignment: .centered,
            animated: animated,
            duration: duration
        )
    }

    func setUpperHeadPose(offset: CGFloat, tiltDegrees: CGFloat, animated: Bool) {
        setUpperHeadPose(
            offset: offset,
            tiltDegrees: tiltDegrees,
            horizontalOffset: 0,
            hingeAlignment: .centered,
            animated: animated,
            duration: Self.stateAnimationDuration
        )
    }

    func setUpperHeadPose(
        offset: CGFloat,
        tiltDegrees: CGFloat,
        horizontalOffset: CGFloat,
        hingeAlignment: UpperHeadHingeAlignment,
        animated: Bool,
        duration: CFTimeInterval
    ) {
        let targetAnchorPoint = hingeAlignment.anchorPoint
        let targetClosedPosition = Self.closedUpperHeadPosition(in: upperHeadLayer.bounds, hingeAlignment: hingeAlignment)
        let targetPosition = CGPoint(
            x: targetClosedPosition.x + horizontalOffset,
            y: targetClosedPosition.y + offset
        )
        let resolvedTiltDegrees = abs(tiltDegrees) < 0.0001 ? 0 : tiltDegrees
        let resolvedHorizontalOffset = abs(horizontalOffset) < 0.0001 ? 0 : horizontalOffset
        let targetTransform = resolvedTiltDegrees == 0
            ? CATransform3DIdentity
            : CATransform3DMakeRotation(resolvedTiltDegrees * (.pi / 180), 0, 0, 1)

        upperHeadClosedPosition = targetClosedPosition
        upperHeadOffset = offset
        upperHeadTiltDegrees = resolvedTiltDegrees
        upperHeadHorizontalOffset = resolvedHorizontalOffset
        upperHeadHingeAlignment = hingeAlignment

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? duration : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        upperHeadLayer.anchorPoint = targetAnchorPoint
        upperHeadLayer.position = targetPosition
        upperHeadLayer.transform = targetTransform
        CATransaction.commit()
    }

    var upperHeadOpenPositionY: CGFloat {
        upperHeadClosedPosition.y + Self.upperHeadOpenOffset
    }

    var upperHeadListeningPositionY: CGFloat {
        upperHeadClosedPosition.y + Self.upperHeadListeningOffset
    }

    func speakingOffset(for normalizedLevel: CGFloat) -> CGFloat {
        SpeechMotionProfile(
            listeningOffset: Self.upperHeadListeningOffset,
            maxSpeakingOffset: Self.upperHeadOpenOffset
        ).offset(for: normalizedLevel)
    }

    func setDisplayScale(_ scale: CGFloat, animated: Bool) {
        let resolvedScale = max(0.01, scale)
        let previousScale = displayScale
        let isExpanding = resolvedScale > previousScale
        displayScale = resolvedScale

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(
            animated
                ? (isExpanding ? Self.expandScaleAnimationDuration : Self.collapseScaleAnimationDuration)
                : 0
        )
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: isExpanding ? .easeOut : .easeInEaseOut)
        )
        rootLayer.transform = CATransform3DMakeScale(resolvedScale, resolvedScale, 1)
        CATransaction.commit()
    }

    func setGlow(active: Bool, error: Bool = false, animated: Bool) {
        let targetOpacity: Float = error ? 0.28 : (active ? 0.18 : 0)

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        characterLayer.shadowOpacity = targetOpacity
        CATransaction.commit()
    }

    func blink() {
        animateBlink(coverLayer: leftEyeBlinkCoverLayer, closedLineLayer: leftEyeClosedLineLayer)
        animateBlink(coverLayer: rightEyeBlinkCoverLayer, closedLineLayer: rightEyeClosedLineLayer)
    }

    private func configureRootLayer() {
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = false
        rootLayer.anchorPoint = CGPoint(x: 0.5, y: 0)

        characterLayer.bounds = CGRect(origin: .zero, size: Self.characterSize)
        characterLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        characterLayer.position = CGPoint(x: Self.canvasSize.width / 2, y: Self.canvasSize.height / 2)
        rootLayer.addSublayer(characterLayer)
    }

    private func configureCharacterLayers() {
        characterLayer.shadowColor = accentGlowColor.cgColor
        characterLayer.shadowOpacity = 0
        characterLayer.shadowRadius = 12
        characterLayer.shadowOffset = .zero

        configureImageLayer(
            fixedBaseLayer,
            named: "YappyFixedBase",
            fallbackColor: NSColor(calibratedRed: 0.38, green: 0.77, blue: 0.86, alpha: 1)
        )
        configureImageLayer(
            upperHeadLayer,
            named: "YappyUpperHead",
            fallbackColor: upperHeadColor
        )
        upperHeadLayer.anchorPoint = Self.upperHeadCenterAnchorPoint
        configureEyeBlinkLayer(leftEyeBlinkCoverLayer)
        configureEyeBlinkLayer(rightEyeBlinkCoverLayer)
        configureClosedEyeLineLayer(leftEyeClosedLineLayer)
        configureClosedEyeLineLayer(rightEyeClosedLineLayer)

        characterLayer.addSublayer(fixedBaseLayer)
        characterLayer.addSublayer(upperHeadLayer)
        upperHeadLayer.addSublayer(leftEyeBlinkCoverLayer)
        upperHeadLayer.addSublayer(rightEyeBlinkCoverLayer)
        upperHeadLayer.addSublayer(leftEyeClosedLineLayer)
        upperHeadLayer.addSublayer(rightEyeClosedLineLayer)
    }

    private static func closedUpperHeadPosition(
        in bounds: CGRect,
        hingeAlignment: UpperHeadHingeAlignment
    ) -> CGPoint {
        let anchorPoint = hingeAlignment.anchorPoint
        return CGPoint(
            x: bounds.minX + (bounds.width * anchorPoint.x),
            y: bounds.minY + (bounds.height * anchorPoint.y)
        )
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

    private func configureEyeBlinkLayer(_ layer: CALayer) {
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.backgroundColor = upperHeadColor.cgColor
        layer.opacity = 0
        layer.transform = CATransform3DMakeScale(1, Self.eyeOpenScaleY, 1)
        layer.zPosition = 2
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    private func configureClosedEyeLineLayer(_ layer: CALayer) {
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.backgroundColor = NSColor.black.cgColor
        layer.opacity = 0
        layer.zPosition = 3
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    private func layoutEyeLayers(in bounds: CGRect) {
        layoutEye(
            coverLayer: leftEyeBlinkCoverLayer,
            closedLineLayer: leftEyeClosedLineLayer,
            center: Self.leftEyeCenter,
            in: bounds
        )
        layoutEye(
            coverLayer: rightEyeBlinkCoverLayer,
            closedLineLayer: rightEyeClosedLineLayer,
            center: Self.rightEyeCenter,
            in: bounds
        )
    }

    private func layoutEye(
        coverLayer: CALayer,
        closedLineLayer: CALayer,
        center: CGPoint,
        in bounds: CGRect
    ) {
        let eyeCenter = CGPoint(
            x: bounds.minX + (bounds.width * center.x),
            y: bounds.minY + (bounds.height * center.y)
        )
        let coverSize = CGSize(
            width: bounds.width * Self.eyeCoverWidthScale,
            height: bounds.height * Self.eyeCoverHeightScale
        )
        let closedLineSize = CGSize(
            width: bounds.width * Self.eyeClosedLineWidthScale,
            height: max(1, bounds.height * Self.eyeClosedLineHeightScale)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coverLayer.bounds = CGRect(origin: .zero, size: coverSize)
        coverLayer.position = eyeCenter
        coverLayer.cornerRadius = coverSize.height / 2
        coverLayer.opacity = 0
        coverLayer.transform = CATransform3DMakeScale(1, Self.eyeOpenScaleY, 1)

        closedLineLayer.bounds = CGRect(origin: .zero, size: closedLineSize)
        closedLineLayer.position = eyeCenter
        closedLineLayer.cornerRadius = closedLineSize.height / 2
        closedLineLayer.opacity = 0
        CATransaction.commit()
    }

    private func animateBlink(coverLayer: CALayer, closedLineLayer: CALayer) {
        coverLayer.removeAnimation(forKey: Self.blinkAnimationKey)
        coverLayer.removeAnimation(forKey: Self.blinkOpacityAnimationKey)
        closedLineLayer.removeAnimation(forKey: Self.closedEyeLineAnimationKey)

        let coverAnimation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        coverAnimation.values = [Self.eyeOpenScaleY, 1, 1, Self.eyeOpenScaleY]
        coverAnimation.keyTimes = [0, 0.45, 0.65, 1]
        coverAnimation.duration = Self.blinkDuration
        coverAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        coverLayer.add(coverAnimation, forKey: Self.blinkAnimationKey)

        let coverOpacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        coverOpacityAnimation.values = [0, 1, 1, 0]
        coverOpacityAnimation.keyTimes = [0, 0.2, 0.8, 1]
        coverOpacityAnimation.duration = Self.blinkDuration
        coverOpacityAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        coverLayer.add(coverOpacityAnimation, forKey: Self.blinkOpacityAnimationKey)

        let closedLineAnimation = CAKeyframeAnimation(keyPath: "opacity")
        closedLineAnimation.values = [0, 0, 1, 1, 0]
        closedLineAnimation.keyTimes = [0, 0.3, 0.45, 0.65, 1]
        closedLineAnimation.duration = Self.blinkDuration
        closedLineAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        closedLineLayer.add(closedLineAnimation, forKey: Self.closedEyeLineAnimationKey)
    }

    private static let eyeOpenScaleY: CGFloat = 0
    private static let eyeCoverWidthScale: CGFloat = 0.108
    private static let eyeCoverHeightScale: CGFloat = 0.14
    private static let eyeClosedLineWidthScale: CGFloat = 0.086
    private static let eyeClosedLineHeightScale: CGFloat = 0.018
    private static let leftEyeCenter = CGPoint(x: 0.419, y: 0.525)
    private static let rightEyeCenter = CGPoint(x: 0.568, y: 0.518)
    private static let blinkAnimationKey = "blink.scale"
    private static let blinkOpacityAnimationKey = "blink.opacity"
    private static let closedEyeLineAnimationKey = "blink.lineOpacity"
}
