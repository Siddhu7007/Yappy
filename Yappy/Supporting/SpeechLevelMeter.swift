// Normalizes microphone RMS into a smoothed 0...1 level for live mouth motion.
import Foundation

struct SpeechLevelMeter {
    let floorDB: Float
    let ceilingDB: Float
    let attackSmoothing: Float
    let releaseSmoothing: Float

    private(set) var normalizedLevel: Float = 0

    init(
        floorDB: Float = -52,
        ceilingDB: Float = -18,
        attackSmoothing: Float = 0.56,
        releaseSmoothing: Float = 0.32
    ) {
        self.floorDB = floorDB
        self.ceilingDB = ceilingDB
        self.attackSmoothing = attackSmoothing
        self.releaseSmoothing = releaseSmoothing
    }

    mutating func process(rms: Float) -> Float {
        let clampedRMS = max(rms, 0.000_001)
        let decibels = 20 * log10f(clampedRMS)
        let rawLevel = normalizedLevel(for: decibels)
        let smoothing = rawLevel > normalizedLevel ? attackSmoothing : releaseSmoothing

        normalizedLevel += (rawLevel - normalizedLevel) * smoothing
        normalizedLevel = max(0, min(1, normalizedLevel))
        return normalizedLevel
    }

    mutating func reset() -> Float {
        let previousLevel = normalizedLevel
        normalizedLevel = 0
        return previousLevel
    }

    private func normalizedLevel(for decibels: Float) -> Float {
        guard ceilingDB > floorDB else {
            return 0
        }

        let rawLevel = (decibels - floorDB) / (ceilingDB - floorDB)
        return max(0, min(1, rawLevel))
    }
}
