import AppKit

struct BrowserChoice: Identifiable {
    let id: String
    let name: String

    @MainActor static func installed() -> [BrowserChoice] {
        var choices = [
            BrowserChoice(id: "com.apple.Safari", name: "Safari"),
            BrowserChoice(id: "com.google.Chrome", name: "Chrome"),
            BrowserChoice(id: "org.mozilla.firefox", name: "Firefox"),
            BrowserChoice(id: "com.microsoft.edgemac", name: "Edge"),
            BrowserChoice(id: "com.brave.Browser", name: "Brave")
        ].filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
        if let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
           let id = Bundle(url: url)?.bundleIdentifier, !choices.contains(where: { $0.id == id }) {
            choices.append(BrowserChoice(id: id, name: url.deletingPathExtension().lastPathComponent))
        }
        return choices
    }

    @MainActor static func defaultID() -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }
}
