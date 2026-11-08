import Testing
@testable import SoeYakuCore

struct HexTests {
    @Test func formatsEveryByteAsTwoLowercaseDigits() {
        #expect([0x00, 0x0A, 0xFF, 0x7B].lowercaseHex == "000aff7b")
        #expect([UInt8]().lowercaseHex == "")
    }
}
