import XCTest
@testable import OpencodeDashboard

final class UsageParserTests: XCTestCase {
    private let sampleHTML = """
    <div class="usage-row">
      <div data-slot="usage-item" class="row">
        <div data-slot="usage-label">Claude Sonnet 4.5</div>
        <div data-slot="usage-value">$3.42</div>
        <div data-slot="reset-time">Resets in 2 days and 7 hours</div>
        <div data-slot="progress-bar" style="width: 42%"></div>
      </div>
      <div data-slot="usage-item" class="row">
        <div data-slot="usage-label">GPT-5 &amp; Codex</div>
        <div data-slot="usage-value">$1.10</div>
        <div data-slot="reset-time">Resets in 5 hours</div>
        <div data-slot="progress-bar" style="width: 100%"></div>
      </div>
      <div data-slot="usage-item" class="row">
        <div data-slot="usage-label">Gemini 3 Flash</div>
        <div data-slot="usage-value">$0.30</div>
        <div data-slot="reset-time">Resets in 35 minutes</div>
        <div data-slot="progress-bar" style="width: 15.7%"></div>
      </div>
    </div>
    """

    func testParsesAllItems() {
        let items = UsageParser.parse(sampleHTML)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].label, "Claude Sonnet 4.5")
        XCTAssertEqual(items[1].label, "GPT-5 & Codex")
        XCTAssertEqual(items[2].label, "Gemini 3 Flash")
    }

    func testPercentIsClampedAndFloored() {
        let items = UsageParser.parse(sampleHTML)
        XCTAssertEqual(items[0].percent, 42)
        XCTAssertEqual(items[1].percent, 100)
        // Fractional percents floor, mirroring parseInt in the Node version.
        XCTAssertEqual(items[2].percent, 15)
    }

    func testResetShortForms() {
        let items = UsageParser.parse(sampleHTML)
        XCTAssertEqual(items[0].resetShort, "2d")
        XCTAssertEqual(items[1].resetShort, "5h")
        XCTAssertEqual(items[2].resetShort, "35m")
    }

    func testValueAndResetText() {
        let items = UsageParser.parse(sampleHTML)
        XCTAssertEqual(items[0].value, "$3.42")
        XCTAssertEqual(items[1].reset, "Resets in 5 hours")
    }

    func testNoItemsWhenCookieExpired() {
        XCTAssertTrue(UsageParser.parse("<html><body>Login required</body></html>").isEmpty)
    }

    func testShortResetUnits() {
        XCTAssertEqual(UsageParser.shortReset("Resets in 1 day"), "1d")
        XCTAssertEqual(UsageParser.shortReset("Resets in 23 minutes"), "23m")
        XCTAssertEqual(UsageParser.shortReset("Resets soon"), "")
    }

    func testEntityDecoding() {
        XCTAssertEqual(UsageParser.decodeEntities("a &amp; b &#39;c&#39; &#x27;d&#x27; &nbsp;"), "a & b 'c' 'd'  ")
    }

    func testPercentFromSingleItem() {
        XCTAssertEqual(UsageParser.barPercent(in: "style=\"width: 7%\"; other"), 7)
        XCTAssertNil(UsageParser.barPercent(in: "no width here"))
    }
}
