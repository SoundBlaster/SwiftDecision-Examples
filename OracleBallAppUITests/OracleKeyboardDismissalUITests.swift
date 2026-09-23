import XCTest

final class OracleKeyboardDismissalUITests: XCTestCase {
  @MainActor
  func testTappingOutsideQuestionFieldDismissesKeyboard() throws {
    let app = XCUIApplication()
    app.launch()

    let questionField = app.textFields["Question for the oracle"]
    XCTAssertTrue(questionField.waitForExistence(timeout: 5))

    questionField.tap()
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

    let appFrame = app.frame
    let fieldFrame = questionField.frame
    let freeAreaTap = app.coordinate(
      withNormalizedOffset: CGVector(
        dx: 0.01,
        dy: fieldFrame.midY / appFrame.height))
    freeAreaTap.tap()

    let keyboardHidden = NSPredicate(format: "exists == false")
    let keyboardHiddenExpectation = XCTNSPredicateExpectation(
      predicate: keyboardHidden,
      object: keyboard)
    XCTAssertEqual(XCTWaiter.wait(for: [keyboardHiddenExpectation], timeout: 5), .completed)
  }
}
