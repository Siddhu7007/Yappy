// Applies hysteresis to normalized microphone levels so the mouth does not chatter.
import Foundation

struct SpeechLevelGate {
    let openThreshold: Float
    let closeThreshold: Float
    let openBufferCount: Int
    let closeBufferCount: Int

    private(set) var isSpeechActive = false
    private var consecutiveOpenBuffers = 0
    private var consecutiveCloseBuffers = 0

    init(
        openThreshold: Float = 0.12,
        closeThreshold: Float = 0.06,
        openBufferCount: Int = 2,
        closeBufferCount: Int = 5
    ) {
        self.openThreshold = openThreshold
        self.closeThreshold = closeThreshold
        self.openBufferCount = openBufferCount
        self.closeBufferCount = closeBufferCount
    }

    mutating func process(level: Float) -> Bool? {
        let normalizedLevel = max(0, min(1, level))

        if isSpeechActive {
            if normalizedLevel <= closeThreshold {
                consecutiveCloseBuffers += 1
            } else {
                consecutiveCloseBuffers = 0
            }

            if consecutiveCloseBuffers >= closeBufferCount {
                isSpeechActive = false
                consecutiveOpenBuffers = 0
                consecutiveCloseBuffers = 0
                return false
            }

            return nil
        }

        if normalizedLevel >= openThreshold {
            consecutiveOpenBuffers += 1
        } else {
            consecutiveOpenBuffers = 0
        }

        if consecutiveOpenBuffers >= openBufferCount {
            isSpeechActive = true
            consecutiveOpenBuffers = 0
            consecutiveCloseBuffers = 0
            return true
        }

        return nil
    }

    mutating func reset() -> Bool {
        let wasSpeechActive = isSpeechActive
        isSpeechActive = false
        consecutiveOpenBuffers = 0
        consecutiveCloseBuffers = 0
        return wasSpeechActive
    }
}
