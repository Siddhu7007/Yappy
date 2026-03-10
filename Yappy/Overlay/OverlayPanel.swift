// Defines the non-activating transparent NSPanel used for the floating overlay.
import AppKit

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
