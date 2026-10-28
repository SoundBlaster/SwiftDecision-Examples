import XCTest

final class OracleWelcomeUITests: XCTestCase {
  @MainActor
  func testAgeConfirmationAndSkippingModel() {
    let app = XCUIApplication()
    app.launchArguments += ["-oracle.resetWelcome"]
    app.launch()

    let next = app.buttons["oracle.welcome.continue"]
    XCTAssertTrue(next.waitForExistence(timeout: 10))
    next.tap()

    let underage = app.buttons["oracle.welcome.underage"]
    XCTAssertTrue(underage.waitForExistence(timeout: 5))
    underage.tap()
    XCTAssertTrue(app.alerts["For adults only"].waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(underage.exists)

    app.buttons["oracle.welcome.confirm-age"].tap()
    let skip = app.buttons["oracle.welcome.skip-model"]
    let installed = app.buttons["oracle.welcome.installed-continue"]
    XCTAssertTrue(skip.waitForExistence(timeout: 5) || installed.exists)
    if skip.exists { skip.tap() } else { installed.tap() }
    XCTAssertTrue(app.textFields["oracle.question.input"].waitForExistence(timeout: 10))
  }
}
