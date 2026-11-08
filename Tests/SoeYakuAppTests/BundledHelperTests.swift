import Testing
@testable import SoeYakuApp

struct BundledHelperTests {
    @Test func missingHelperThrowsTheCallersMessageOutsideTheAppBundle() {
        do {
            _ = try BundledHelper.modelStarter(missingMessage: "見つかりません。")
            Issue.record("expected a throw")
        } catch {
            #expect(error.localizedDescription == "見つかりません。")
        }
    }
}
