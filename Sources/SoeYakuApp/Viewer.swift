import CoreGraphics

/// The app that shows the open document, and how its front window is recognised as that document.
enum Viewer: Equatable {
    /// Preview showing a PDF; with a name, only the window titled with it is followed.
    case preview(documentName: String?)
    /// A browser showing an HTML page whose window title is one of `titles`.
    case browser(bundleID: String, titles: [String])

    static let previewBundleID = "com.apple.Preview"

    var bundleID: String {
        switch self {
        case .preview: Self.previewBundleID
        case .browser(let bundleID, _): bundleID
        }
    }

    var name: String {
        switch self {
        case .preview: "プレビュー"
        case .browser: "ブラウザ"
        }
    }

    /// The front window of the viewer process when it shows this document, with its frame in global top-left coordinates.
    @MainActor func frontWindow(in list: [[String: Any]], pid: pid_t) -> (CGWindowID, CGRect)? {
        switch self {
        case .preview(let documentName): WindowFollower.frontDocumentWindow(in: list, pid: pid, documentName: documentName)
        case .browser(_, let titles): WindowFollower.frontBrowserWindow(in: list, pid: pid, titles: titles)
        }
    }
}
