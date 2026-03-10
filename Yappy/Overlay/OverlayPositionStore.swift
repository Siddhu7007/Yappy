// Persists the overlay origin and resolves a safe on-screen frame for launch and recentering.
import CoreGraphics
import Foundation

final class OverlayPositionStore {
    private enum Keys {
        static let x = "overlay.origin.x"
        static let y = "overlay.origin.y"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(origin: CGPoint) {
        userDefaults.set(origin.x, forKey: Keys.x)
        userDefaults.set(origin.y, forKey: Keys.y)
    }

    func currentOrigin(
        visibleFrames: [CGRect],
        mainVisibleFrame: CGRect,
        panelSize: CGSize
    ) -> CGPoint {
        let defaultOrigin = CGPoint(
            x: mainVisibleFrame.midX - (panelSize.width / 2),
            y: mainVisibleFrame.minY + 32
        )

        guard
            let storedX = userDefaults.object(forKey: Keys.x) as? Double,
            let storedY = userDefaults.object(forKey: Keys.y) as? Double,
            storedX.isFinite,
            storedY.isFinite
        else {
            return defaultOrigin
        }

        let savedOrigin = CGPoint(x: storedX, y: storedY)
        let savedFrame = CGRect(origin: savedOrigin, size: panelSize)

        if let visibleFrame = visibleFrames.first(where: { $0.intersects(savedFrame) || $0.contains(savedOrigin) }) {
            return clamped(origin: savedOrigin, visibleFrame: visibleFrame, panelSize: panelSize)
        }

        return defaultOrigin
    }

    func defaultOrigin(mainVisibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        CGPoint(
            x: mainVisibleFrame.midX - (panelSize.width / 2),
            y: mainVisibleFrame.minY + 32
        )
    }

    private func clamped(origin: CGPoint, visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        let minimumX = visibleFrame.minX
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let minimumY = visibleFrame.minY
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)

        return CGPoint(
            x: min(max(origin.x, minimumX), maximumX),
            y: min(max(origin.y, minimumY), maximumY)
        )
    }
}
