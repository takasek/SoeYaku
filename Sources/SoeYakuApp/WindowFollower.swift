import AppKit
import ScreenCaptureKit
import SoeYakuCore
import SoeYakuVision

/// Reads the front window of the viewer app and reports which sentence is under the pointer.
/// It captures only that window, and only while the viewer is the active app and the pointer is inside the window.
@MainActor final class WindowFollower {
    enum Problem: LocalizedError {
        case permission
        var errorDescription: String? {
            "画面収録が許可されていません。システム設定の「プライバシーとセキュリティ」→「画面とシステムオーディオの録音」で SoeYaku を許可し、SoeYaku を開き直してください。"
        }
    }

    static let previewBundleID = "com.apple.Preview"
    private let bundleID: String
    private var locator: Locator
    private var task: Task<Void, Never>?
    private var window: SCWindow?
    private var lastImage: CFData?
    private var lastLines: [TextLine] = []
    var onResult: ((LocateResult) -> Void)?
    var onProblem: ((String) -> Void)?

    init(document: SourceDocument, bundleID: String = WindowFollower.previewBundleID) {
        self.bundleID = bundleID
        locator = Locator(index: DocumentIndex(document))
    }

    /// Asks for the screen recording permission when it is missing and does not start without it.
    func start() throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw Problem.permission
        }
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        lastImage = nil
        lastLines = []
    }

    private func tick() async {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID,
              let (windowID, frame) = Self.frontWindow(of: app.processIdentifier) else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let pointer = ScreenGeometry.normalizedPointer(mouse: NSEvent.mouseLocation, primaryScreenHeight: primaryHeight,
                                                             windowFrame: frame) else { return }
        do {
            let image = try await capture(windowID: windowID, size: frame.size)
            guard !Task.isCancelled else { return }
            let data = image.dataProvider?.data
            if let data, let lastImage, CFEqual(data, lastImage) {
                // Same pixels as last time: only the pointer can have moved, so skip the OCR.
            } else {
                lastLines = try await TextRecognizer.lines(in: image)
                lastImage = data
            }
            guard !Task.isCancelled else { return }
            onResult?(locator.locate(lines: lastLines, pointer: pointer))
        } catch {
            onProblem?(error.localizedDescription)
        }
    }

    private func capture(windowID: CGWindowID, size: CGSize) async throws -> CGImage {
        if window?.windowID != windowID {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            window = content.windows.first { $0.windowID == windowID }
        }
        guard let window else { throw CaptureError.windowGone }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private enum CaptureError: LocalizedError {
        case windowGone
        var errorDescription: String? { "プレビューのウインドウを取得できませんでした。" }
    }

    /// The topmost normal window of the process, with its frame in global top-left coordinates.
    private static func frontWindow(of pid: pid_t) -> (CGWindowID, CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            return (number, frame)
        }
        return nil
    }
}
