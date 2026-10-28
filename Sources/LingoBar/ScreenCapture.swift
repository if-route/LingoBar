import AppKit
import CoreGraphics
import LingoBarCore
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "LingoBar does not have Screen Recording permission."
        case .displayNotFound: return "Could not find the display for the selected region."
        case .failed(let message): return "Screen capture failed: \(message)"
        }
    }
}

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures `globalRect` (AppKit global points) on `screen` at the screen's
    /// native pixel density, excluding LingoBar's own windows. Returns the image
    /// and the rect it actually covers (the selection clipped to the screen).
    @MainActor
    static func capture(globalRect: CGRect, on screen: NSScreen) async throws -> (image: CGImage, region: CGRect) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw ScreenCaptureError.displayNotFound
        }
        return try await capture(globalRect: globalRect, displayID: displayID, screenFrame: screen.frame, scale: screen.backingScaleFactor)
    }

    static func capture(globalRect: CGRect, displayID: CGDirectDisplayID, screenFrame: CGRect, scale: CGFloat) async throws -> (image: CGImage, region: CGRect) {

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw hasPermission ? ScreenCaptureError.failed(error.localizedDescription) : ScreenCaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        // Clip to the screen in case the selection touches an edge.
        let clipped = globalRect.intersection(screenFrame)
        let pixels = CoordinateMapper.pixelSize(for: clipped, scale: scale)

        let config = SCStreamConfiguration()
        config.sourceRect = CoordinateMapper.displayLocalTopLeftRect(globalRect: clipped, screenFrame: screenFrame)
        config.width = pixels.width
        config.height = pixels.height
        config.showsCursor = false
        config.scalesToFit = false

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return (image, clipped)
        } catch {
            throw hasPermission ? ScreenCaptureError.failed(error.localizedDescription) : ScreenCaptureError.permissionDenied
        }
    }

    @MainActor
    static func showPermissionHelp() {
        // Registers LingoBar in the Screen Recording list (shows the system prompt the first time).
        _ = CGRequestScreenCaptureAccess()

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        LingoBar needs Screen Recording permission to read text in the area you select.

        Turn on LingoBar in System Settings › Privacy & Security › Screen Recording, then quit and reopen LingoBar.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
