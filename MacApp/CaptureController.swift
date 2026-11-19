import AppKit
// Older SDKs lack Sendable annotations; capture objects stay confined to MainActor.
@preconcurrency import ScreenCaptureKit
import SnapLaterCore

enum CaptureFailure: Error {
    case permission, unavailable
    var message: String {
        switch self {
        case .permission: "Allow Snipstep in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. You can also import an image without screen access."
        case .unavailable: "The screen could not be captured. Nothing was uploaded. Try again or import an image."
        }
    }
}

@MainActor final class CaptureController {
    func capture() async throws -> Data {
        // Capture the entire display under the pointer, without activating SnapLater.
        let displayID = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == (displayID?.uint32Value ?? CGMainDisplayID()) }) else {
                throw CaptureFailure.unavailable
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = CGDisplayPixelsWide(display.displayID)
            configuration.height = CGDisplayPixelsHigh(display.displayID)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return try await Task.detached(priority: .userInitiated) { try ImageFiles.png(image) }.value
        } catch let error as NSError {
            if error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue {
                throw CaptureFailure.permission
            }
            throw CaptureFailure.unavailable
        }
    }
}
