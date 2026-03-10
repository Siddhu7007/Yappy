// Verifies the overlay defaults to bottom-center and falls back safely when saved positions are invalid.
import CoreGraphics
import Foundation
import Testing
@testable import Yappy

@MainActor
struct OverlayPositionStoreTests {
    @Test
    func returnsBottomCenterWhenNoSavedOriginExists() {
        let defaults = makeDefaults()
        let store = OverlayPositionStore(userDefaults: defaults)
        let mainVisibleFrame = CGRect(x: 100, y: 40, width: 1000, height: 700)
        let panelSize = CGSize(width: 168, height: 168)

        let origin = store.currentOrigin(
            visibleFrames: [mainVisibleFrame],
            mainVisibleFrame: mainVisibleFrame,
            panelSize: panelSize
        )

        #expect(origin == CGPoint(x: 516, y: 72))
    }

    @Test
    func preservesSavedOriginWhenStillVisible() {
        let defaults = makeDefaults()
        let store = OverlayPositionStore(userDefaults: defaults)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let savedOrigin = CGPoint(x: 220, y: 180)

        store.save(origin: savedOrigin)

        let origin = store.currentOrigin(
            visibleFrames: [visibleFrame],
            mainVisibleFrame: visibleFrame,
            panelSize: CGSize(width: 168, height: 168)
        )

        #expect(origin == savedOrigin)
    }

    @Test
    func fallsBackToMainScreenWhenSavedOriginIsOffscreen() {
        let defaults = makeDefaults()
        let store = OverlayPositionStore(userDefaults: defaults)
        let mainVisibleFrame = CGRect(x: 20, y: 30, width: 1280, height: 780)

        store.save(origin: CGPoint(x: -2000, y: -1400))

        let origin = store.currentOrigin(
            visibleFrames: [mainVisibleFrame],
            mainVisibleFrame: mainVisibleFrame,
            panelSize: CGSize(width: 168, height: 168)
        )

        #expect(origin == CGPoint(x: 576, y: 62))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OverlayPositionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
