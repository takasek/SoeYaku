import AppKit
import ScreenCaptureKit

/// Captures one screen region per call. One instance serves one frame session and keeps its filter and configuration between frames.
@MainActor final class FrameCapture {
    /// A display whose arrangement or resolution changed needs a new source rectangle and image size.
    private struct Key: Equatable {
        let region: FrameRegion
        let displayBounds: CGRect
        let displayPixels: CGSize?
    }

    private struct Setup {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    private let cache = CaptureSetupCache<Key, Setup>()

    func image(in region: FrameRegion) async throws -> CGImage {
        // Preflight only: the frame loop must never raise the permission prompt.
        guard CGPreflightScreenCaptureAccess() else { throw ScreenRecording.Problem.permission }
        let mode = CGDisplayCopyDisplayMode(region.displayID)
        let key = Key(region: region, displayBounds: CGDisplayBounds(region.displayID),
                      displayPixels: mode.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) })
        return try await cache.capture(for: key, prepare: { try await Self.setup(for: region) }, shoot: { try await Self.shoot($0) })
    }

    private static func setup(for region: FrameRegion) async throws -> (setup: Setup, keep: Bool) {
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
        // A filter made before SoeYaku had a window on screen would not leave out its windows, so it is not kept.
        return (Setup(filter: filter, configuration: configuration), keep: !own.isEmpty)
    }

    private static func shoot(_ setup: Setup) async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: setup.filter, configuration: setup.configuration)
    }
}

/// Keeps the setup prepared for the last key, so that a frame loop does not prepare one for every frame.
@MainActor final class CaptureSetupCache<Key: Equatable, Setup> {
    private var kept: (key: Key, setup: Setup)?

    /// `prepare` also says whether its setup may be kept for later frames.
    /// A capture that fails with a kept setup is tried once more with a fresh one, as it was when every frame prepared its own.
    func capture<Image>(for key: Key, prepare: @MainActor () async throws -> (setup: Setup, keep: Bool),
                        shoot: @MainActor (Setup) async throws -> Image) async throws -> Image {
        if let kept, kept.key == key {
            do { return try await shoot(kept.setup) } catch { self.kept = nil }
        }
        let prepared = try await prepare()
        kept = prepared.keep ? (key, prepared.setup) : nil
        do { return try await shoot(prepared.setup) } catch {
            kept = nil
            throw error
        }
    }
}
