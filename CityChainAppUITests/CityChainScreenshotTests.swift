import XCTest

@MainActor
final class CityChainScreenshotTests: XCTestCase {
  func testScreenshots() throws {
    continueAfterFailure = false
    executionTimeAllowance = 240
    try ScreenshotScenario.run { app, capture in
      let atlas = app.buttons["City atlas"]
      XCTAssertTrue(atlas.waitForExistence(timeout: 20))
      XCTAssertFalse(app.alerts.firstMatch.exists)
      try capture.checkpoint("01-main", presentation: "main")
      atlas.tap()
      XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["Every explorer can use an atlas!"].exists)
      try capture.checkpoint("02-atlas", presentation: "atlas")
      app.buttons["Done"].tap()
      XCTAssertTrue(atlas.waitForExistence(timeout: 10))
    }
  }

  func testRuntimeOptOut() throws {
    try ScreenshotScenario.verifyRuntimeOptOut(readyIdentifier: "City atlas")
  }
}
