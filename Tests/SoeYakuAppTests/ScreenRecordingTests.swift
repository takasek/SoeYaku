import Testing
@testable import SoeYakuApp

struct ScreenRecordingTests {
    @Test func permissionProblemExplainsHowToAllowScreenRecording() {
        #expect(ScreenRecording.Problem.permission.localizedDescription
            == "画面収録が許可されていません。システム設定の「プライバシーとセキュリティ」→「画面とシステムオーディオの録音」で SoeYaku を許可し、SoeYaku を開き直してください。")
    }
}
