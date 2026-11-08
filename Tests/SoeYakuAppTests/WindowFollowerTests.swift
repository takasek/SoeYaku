import AppKit
import SoeYakuCore
import Testing
@testable import SoeYakuApp

@MainActor struct WindowFollowerTests {
    @Test func viewerSelectionSkipsSharingChromeAndUsesTheFrontDocument() throws {
        let toolbar = windowInfo(1, title: "Window", frame: CGRect(x: 16, y: 56, width: 66, height: 20))
        let document = windowInfo(2, title: "Book.pdf", frame: CGRect(x: 0, y: 40, width: 900, height: 1129))
        let match = try #require(WindowFollower.frontDocumentWindow(in: [toolbar, document], pid: 10, documentName: "Book.pdf"))
        #expect(match.0 == 2)
        #expect(match.1 == CGRect(x: 0, y: 40, width: 900, height: 1129))
        let otherPDF = windowInfo(3, title: "Other.pdf", frame: CGRect(x: 0, y: 40, width: 900, height: 1129))
        #expect(WindowFollower.frontDocumentWindow(in: [toolbar, otherPDF, document], pid: 10, documentName: "Book.pdf") == nil)
        let image = windowInfo(4, title: "Photo.png", frame: CGRect(x: 0, y: 40, width: 900, height: 1129))
        #expect(WindowFollower.frontDocumentWindow(in: [toolbar, image, document], pid: 10, documentName: "Book.pdf") == nil)
    }

    private func windowInfo(_ id: CGWindowID, title: String, frame: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid_t(10), kCGWindowLayer as String: 0,
         kCGWindowName as String: title, kCGWindowBounds as String: frame.dictionaryRepresentation]
    }

    @Test func browserSelectionMatchesTheFrontPageAndNeverSearchesBehindAnotherTab() throws {
        let chrome = windowInfo(1, title: "Window", frame: CGRect(x: 0, y: 30, width: 66, height: 20))
        let page = windowInfo(2, title: "Reading & Results – Google Chrome", frame: CGRect(x: 0, y: 40, width: 900, height: 1000))
        let match = try #require(WindowFollower.frontBrowserWindow(in: [chrome, page], pid: 10, titles: ["Reading & Results"]))
        #expect(match.0 == 2)
        let other = windowInfo(3, title: "Another page – Google Chrome", frame: CGRect(x: 0, y: 40, width: 900, height: 1000))
        #expect(WindowFollower.frontBrowserWindow(in: [chrome, other, page], pid: 10, titles: ["Reading & Results"]) == nil)
        #expect(WindowFollower.frontBrowserWindow(in: [page], pid: 10, titles: ["Reading"]) == nil)
        #expect(WindowFollower.frontBrowserWindow(in: [page], pid: 11, titles: ["Reading & Results"]) == nil)
        let safari = windowInfo(4, title: "Reading & Results", frame: CGRect(x: 0, y: 40, width: 900, height: 1000))
        #expect(WindowFollower.frontBrowserWindow(in: [safari], pid: 10, titles: ["Reading & Results"])?.0 == 4)
    }

    @Test func thePointerOverTheTranslationPanelDoesNotFollowThePreviewBehindIt() {
        _ = NSApplication.shared
        let translation = SpacePanel(contentRect: CGRect(x: 600, y: 400, width: 300, height: 300),
                                  styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { translation.orderOut(nil) }
        let document = SourceDocument(fingerprint: "f", title: "T", sentences: [])
        let follower = WindowFollower(document: document, excludedWindows: [translation])
        let viewer = CGRect(x: 100, y: 200, width: 1000, height: 800)
        let mouse = CGPoint(x: 700, y: 500)
        translation.orderFrontRegardless()
        let viewerID = CGWindowID(777)
        let viewerInfo = windowInfo(viewerID, title: "Book.pdf", frame: viewer)
        let panelInfo = windowInfo(CGWindowID(translation.windowNumber), title: "Translation", frame: CGRect(x: 600, y: 500, width: 300, height: 300))
        let panelInFront = [panelInfo, viewerInfo]
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer, viewerWindowID: viewerID, windows: panelInFront) == nil)
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer, viewerWindowID: viewerID, windows: [viewerInfo, panelInfo]) == CGPoint(x: 0.6, y: 0.625))
        #expect(follower.normalizedPointer(mouse: CGPoint(x: 300, y: 500), primaryScreenHeight: 1200, viewerFrame: viewer, viewerWindowID: viewerID, windows: panelInFront) == CGPoint(x: 0.2, y: 0.625))
        translation.simulatedActiveSpace = false
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer, viewerWindowID: viewerID, windows: panelInFront) == CGPoint(x: 0.6, y: 0.625))
        translation.simulatedActiveSpace = true
        translation.orderOut(nil)
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer, viewerWindowID: viewerID, windows: panelInFront) == CGPoint(x: 0.6, y: 0.625))
    }
}

@MainActor private final class SpacePanel: NSPanel {
    var simulatedActiveSpace = true
    override var isOnActiveSpace: Bool { simulatedActiveSpace }
}
