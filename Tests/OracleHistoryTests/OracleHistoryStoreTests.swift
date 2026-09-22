import Foundation
import XCTest
@testable import OracleHistory
import OracleGame

@MainActor
final class OracleHistoryStoreTests: XCTestCase {
  func testAppendPersistsNewestFirstAndLoadsAfterRecreation() {
    let (defaults, key) = makeDefaults()
    let store = OracleHistoryStore(defaults: defaults, storageKey: key)

    store.append(question: "Will it work?", answer: makeAnswer("Yes"), createdAt: Date(timeIntervalSince1970: 1))
    store.append(question: "Tea or coffee?", answer: makeAnswer("Tea"), createdAt: Date(timeIntervalSince1970: 2))

    let reloaded = OracleHistoryStore(defaults: defaults, storageKey: key)
    XCTAssertEqual(reloaded.entries.map(\.question), ["Tea or coffee?", "Will it work?"])
    XCTAssertEqual(reloaded.entries.map(\.answer), ["Tea", "Yes"])
  }

  func testAppendKeepsOnlyConfiguredNumberOfEntries() {
    let (defaults, key) = makeDefaults()
    let store = OracleHistoryStore(defaults: defaults, storageKey: key, limit: 2)

    for number in 1 ... 3 {
      store.append(question: "Question \(number)", answer: makeAnswer("Answer \(number)"))
    }

    XCTAssertEqual(store.entries.map(\.question), ["Question 3", "Question 2"])
  }

  func testRemoveDeletesOnlyMatchingEntryAndPersists() {
    let (defaults, key) = makeDefaults()
    let store = OracleHistoryStore(defaults: defaults, storageKey: key)
    let first = store.append(question: "First?", answer: makeAnswer("First"))
    let second = store.append(question: "Second?", answer: makeAnswer("Second"))

    store.remove(id: second.id)

    XCTAssertEqual(store.entries.map(\.id), [first.id])
    XCTAssertEqual(OracleHistoryStore(defaults: defaults, storageKey: key).entries.map(\.id), [first.id])
  }

  func testRemoveAllClearsPersistedHistory() {
    let (defaults, key) = makeDefaults()
    let store = OracleHistoryStore(defaults: defaults, storageKey: key)
    store.append(question: "Question?", answer: makeAnswer("Answer"))

    store.removeAll()

    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertTrue(OracleHistoryStore(defaults: defaults, storageKey: key).entries.isEmpty)
  }

  private func makeDefaults() -> (UserDefaults, String) {
    let key = "test.oracle-history.\(UUID().uuidString)"
    return (UserDefaults(suiteName: key)!, key)
  }

  private func makeAnswer(_ text: String) -> OracleAnswer {
    OracleAnswer(mode: .noul, displayText: text, confidence: 0.9, source: .offlineFixture)
  }
}
