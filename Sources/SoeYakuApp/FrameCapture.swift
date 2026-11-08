import AppKit
import ScreenCaptureKit

@MainActor enum FrameCapture {
    static func image(in region: FrameRegion) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenRecording.Problem.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw AppFailure("選んだ画面が見つかりません。枠を選び直してください。")
        }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let area = CGRect(x: region.normalized.minX * display.frame.width, y: region.normalized.minY * display.frame.height,
                          width: region.normalized.width * display.frame.width, height: region.normalized.height * display.frame.height)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area
        configuration.width = max(1, Int(area.width * CGFloat(filter.pointPixelScale)))
        configuration.height = max(1, Int(area.height * CGFloat(filter.pointPixelScale)))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
