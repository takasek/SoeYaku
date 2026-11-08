import CoreGraphics
import Foundation

/// The screen recording permission that window following and frame capture both need.
enum ScreenRecording {
    enum Problem: LocalizedError {
        case permission
        var errorDescription: String? {
            "画面収録が許可されていません。システム設定の「プライバシーとセキュリティ」→「画面とシステムオーディオの録音」で SoeYaku を許可し、SoeYaku を開き直してください。"
        }
    }

    /// Asks for the permission when it is missing and throws `Problem.permission` so the caller does not start without it.
    static func requestAccess() throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw Problem.permission
        }
    }
}
