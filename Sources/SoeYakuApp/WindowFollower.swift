import AppKit
import ScreenCaptureKit
import SoeYakuCore
import SoeYakuVision
import UniformTypeIdentifiers

/// Reads the front window of the viewer app and reports which sentence is under the pointer.
/// It captures only that window, and only while the viewer is the active app and the pointer is inside the window.
@MainActor final class WindowFollower {
    static let previewBundleID = "com.apple.Preview"
    private let bundleID: String
    private let documentName: String?
    private let browserTitles: [String]?
    private var locator: Locator
    private var task: Task<Void, Never>?
    private var window: SCWindow?
    private var lastImage: CFData?
    private var lastLines: [TextLine] = []
    private let excludedWindows: [NSWindow]
    var onResult: ((LocateResult) -> Void)?
    var onProblem: ((String) -> Void)?

    init(document: SourceDocument, bundleID: String = WindowFollower.previewBundleID, excludedWindows: [NSWindow] = [], documentName: String? = nil, browserTitles: [String]? = nil) {
        self.bundleID = bundleID
        self.documentName = documentName
        self.browserTitles = browserTitles
        self.excludedWindows = excludedWindows
        locator = Locator(index: DocumentIndex(document))
    }

    /// Asks for the screen recording permission when it is missing and does not start without it.
    func start() throws {
        try ScreenRecording.requestAccess()
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
              let (windowID, frame) = frontWindow(of: app.processIdentifier) else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard normalizedPointer(mouse: NSEvent.mouseLocation, primaryScreenHeight: primaryHeight, viewerFrame: frame, viewerWindowID: windowID) != nil else { return }
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
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let (currentWindowID, currentFrame) = frontWindow(of: app.processIdentifier),
                  currentWindowID == windowID, currentFrame == frame,
                  let pointer = normalizedPointer(mouse: NSEvent.mouseLocation, primaryScreenHeight: primaryHeight, viewerFrame: frame, viewerWindowID: windowID)
            else { return }
            onResult?(locator.locate(lines: lastLines, pointer: pointer))
        } catch {
            onProblem?(error.localizedDescription)
        }
    }

    func normalizedPointer(mouse: CGPoint, primaryScreenHeight: CGFloat, viewerFrame: CGRect, viewerWindowID: CGWindowID, windows: [[String: Any]]? = nil) -> CGPoint? {
        guard let pointer = ScreenGeometry.normalizedPointer(mouse: mouse, primaryScreenHeight: primaryScreenHeight, windowFrame: viewerFrame) else { return nil }
        let ignored = Set(excludedWindows.filter { !$0.isVisible || !$0.isOnActiveSpace || $0.isMiniaturized }.map { CGWindowID($0.windowNumber) })
        let list = windows ?? (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        let point = CGPoint(x: mouse.x, y: primaryScreenHeight - mouse.y)
        for info in list {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID, !ignored.contains(number),
                  (info[kCGWindowIsOnscreen as String] as? Bool ?? true),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            if (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.cursorWindow)),
               info[kCGWindowOwnerName as String] as? String == "Window Server" { continue }
            guard let frame = Self.frame(of: info), frame.contains(point) else { continue }
            // A normal-level translation window behind the reader must not block following.
            return number == viewerWindowID ? pointer : nil
        }
        return nil
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
        var errorDescription: String? { "閲覧元のウインドウを取得できませんでした。" }
    }

    /// The topmost normal window of the process, with its frame in global top-left coordinates.
    private func frontWindow(of pid: pid_t) -> (CGWindowID, CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        if let browserTitles { return Self.frontBrowserWindow(in: list, pid: pid, titles: browserTitles) }
        return Self.frontDocumentWindow(in: list, pid: pid, documentName: documentName)
    }

    private static func isNormalWindow(_ info: [String: Any], pid: pid_t) -> Bool {
        (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0
    }

    private static func frame(of info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    static func frontBrowserWindow(in list: [[String: Any]], pid: pid_t, titles: [String]) -> (CGWindowID, CGRect)? {
        let suffixes = ["Google Chrome", "Mozilla Firefox", "Microsoft Edge", "Brave", "Safari", "Arc"]
        func normalized(_ title: String) -> String {
            var value = title.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in suffixes {
                for separator in [" - ", " – ", " — "] where value.hasSuffix(separator + suffix) {
                    value.removeLast((separator + suffix).count)
                }
            }
            return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let expected = Set(titles.map(normalized).filter { !$0.isEmpty })
        for info in list where isNormalWindow(info, pid: pid) {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let frame = frame(of: info), frame.width >= 300, frame.height >= 200,
                  let title = info[kCGWindowName as String] as? String else { continue }
            // Match only the front normal browser window; never follow a matching page behind another one.
            return expected.contains(normalized(title)) ? (number, frame) : nil
        }
        return nil
    }

    static func frontDocumentWindow(in list: [[String: Any]], pid: pid_t, documentName: String?) -> (CGWindowID, CGRect)? {
        for info in list where isNormalWindow(info, pid: pid) {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let frame = frame(of: info),
                  let title = info[kCGWindowName as String] as? String,
                  let type = UTType(filenameExtension: (title as NSString).pathExtension),
                  type.conforms(to: .pdf) || type.conforms(to: .image) else { continue }
            // Preview also owns small sharing controls at layer zero. Only its front document is eligible.
            if let documentName, title.caseInsensitiveCompare(documentName) != .orderedSame { return nil }
            return (number, frame)
        }
        return nil
    }
}
