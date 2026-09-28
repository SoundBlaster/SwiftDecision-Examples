import XCTest

final class CityChainScoutMapUITests: XCTestCase {
  @MainActor
  func testTappingIdleScoutOpensMapAndCloseReturnsToGame() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launch()

    let scout = idleScout(in: app)
    XCTAssertTrue(scout.waitForExistence(timeout: 15), "The idle Scout should be available")
    XCTAssertTrue(scout.isHittable, "The idle Scout should accept a tap")
    scout.tap()

    let closeMap = app.buttons["cityAtlas.map.close"]
    let scoutOpenedMap = closeMap.waitForExistence(timeout: 5)
    if scoutOpenedMap {
      closeMap.tap()
    }

    XCTAssertTrue(scout.waitForExistence(timeout: 10), "Closing the map should return to the game")

    let cityField = app.textFields["City name"]
    XCTAssertTrue(cityField.waitForExistence(timeout: 5))
    cityField.tap()
    cityField.typeText("Austin")
    app.buttons["Send city"].tap()

    let dismissFeedback = app.buttons["Dismiss message"]
    XCTAssertTrue(dismissFeedback.waitForExistence(timeout: 20), "Scout should finish the turn")
    dismissFeedback.tap()

    let idleScout = self.idleScout(in: app)
    XCTAssertTrue(idleScout.waitForExistence(timeout: 10), "The dismissed reply should return Scout to idle")
    XCTAssertTrue(idleScout.isHittable, "The after-turn idle Scout should accept a tap")
    let toolbarMap = app.buttons["Pocket Atlas map"]
    let toolbarAvailable = toolbarMap.waitForExistence(timeout: 2)
    var toolbarOpenedMap = false
    if toolbarAvailable {
      toolbarMap.tap()
      toolbarOpenedMap = closeMap.waitForExistence(timeout: 5)
    }
    if toolbarOpenedMap {
      closeMap.tap()
    }

    idleScout.tap()
    let afterTurnScoutOpenedMap = closeMap.waitForExistence(timeout: 5)
    if afterTurnScoutOpenedMap {
      closeMap.tap()
    }
    XCTAssertTrue(scoutOpenedMap, "Tapping the initial idle Scout should open the map")
    if toolbarAvailable {
      XCTAssertTrue(toolbarOpenedMap, "The route map toolbar should open the map")
    }
    XCTAssertTrue(afterTurnScoutOpenedMap, "Tapping the after-turn idle Scout should open the map")
    XCTAssertTrue(idleScout.waitForExistence(timeout: 10), "Closing the map should return to the after-turn game")
  }

  private func idleScout(in app: XCUIApplication) -> XCUIElement {
    let mapPanelScout = app.buttons["cityChain.scout.mapPanel.openMap"]
    if mapPanelScout.waitForExistence(timeout: 2) {
      return mapPanelScout
    }
    return app.buttons["cityChain.scout.openMap"]
  }
}
