import XCTest

final class OracleKeyboardDismissalUITests: XCTestCase {
  @MainActor
  func testInferenceProviderSelectionPersistsWithoutAKey() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    app.buttons["oracle.header.settings"].tap()
    let picker = app.buttons["oracle.settings.provider"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    picker.tap()
    app.buttons["Apple Intelligence"].tap()
    XCTAssertTrue(app.switches["oracle.settings.normalize-apple-output"].waitForExistence(timeout: 5))
    picker.tap()
    app.buttons["None"].tap()
    XCTAssertTrue(app.staticTexts["None · offline answers"].waitForExistence(timeout: 5))
    app.buttons["oracle.settings.done"].tap()
    app.terminate()
    app.launch()
    app.buttons["oracle.header.settings"].tap()
    XCTAssertTrue(app.staticTexts["None · offline answers"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testTappingOutsideQuestionFieldDismissesKeyboard() throws {
    let app = XCUIApplication()
    app.launch()

    let questionField = app.textFields["oracle.question.input"]
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

  @MainActor
  func testTappingTheOracleBallDismissesKeyboard() throws {
    let app = XCUIApplication()
    app.launch()

    let questionField = app.textFields["oracle.question.input"]
    XCTAssertTrue(questionField.waitForExistence(timeout: 5))
    questionField.tap()

    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

    let oracleBall = app.otherElements.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Oracle answer:")).firstMatch
    XCTAssertTrue(oracleBall.waitForExistence(timeout: 5))
    oracleBall.tap()

    let keyboardHidden = NSPredicate(format: "exists == false")
    let keyboardHiddenExpectation = XCTNSPredicateExpectation(
      predicate: keyboardHidden,
      object: keyboard)
    XCTAssertEqual(XCTWaiter.wait(for: [keyboardHiddenExpectation], timeout: 5), .completed)
  }
}
