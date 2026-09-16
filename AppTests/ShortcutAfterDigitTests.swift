import XCTest
@testable import VietTelex

/// Issue #82 (16/09/2026): gõ tắt `h→giờ` nở luôn trong "5h" thành "5giờ" vì chữ số
/// là boundary trong Telex — từ "h" không biết nó dính số. Chuẩn Unikey: "5h" là một
/// token, gõ tắt chỉ nở khi từ đứng riêng ("5 h" → "5 giờ").
final class ShortcutAfterDigitTests: XCTestCase {
    func testDigitBeforeWordBlocksExpansion() {
        XCTAssertFalse(TelexInputController.shortcutExpansionAllowed(afterDigit: true))   // 5h, 5k, 10k
        XCTAssertTrue(TelexInputController.shortcutExpansionAllowed(afterDigit: false))   // h, "5 h", "(h"
    }

    func testDigitDetection() {
        for c in "0123456789".utf8 { XCTAssertTrue(TelexInputController.isAsciiDigit(c)) }
        for c in " (.,-h".utf8 { XCTAssertFalse(TelexInputController.isAsciiDigit(c), String(UnicodeScalar(c))) }
        XCTAssertFalse(TelexInputController.isAsciiDigit(nil))
    }
}
