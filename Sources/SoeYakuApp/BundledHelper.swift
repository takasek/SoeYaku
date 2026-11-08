import Foundation

/// The helpers shipped inside SoeYaku.app, which exist only when the app is launched from its bundle.
enum BundledHelper {
    /// `missingMessage` is thrown as an `AppFailure` when `Helpers/start-model` is not an executable next to the app's `MacOS` folder.
    static func modelStarter(missingMessage: String) throws -> URL {
        guard let helper = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Helpers/start-model"), FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw AppFailure(missingMessage)
        }
        return helper
    }
}
