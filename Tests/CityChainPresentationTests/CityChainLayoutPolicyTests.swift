import CityChainPresentation
import Testing

private typealias Context = CityChainLayoutContext

@Test(arguments: [390.0, 600, 713, 714, 1024])
func expandedLayoutRequiresBothReadablePanes(width: Double) {
  let result = CityChainLayoutPolicy().decide(Context(
    width: width, height: 800, hasRegularWidth: true, hasRegularHeight: true))
  #expect(result == (width >= 714 ? .expandedPanes : .singleColumn))
}

@Test func narrowOrShortWindowAndAccessibilityPreferFocusedGame() {
  for context in [
    Context(width: 1024, height: 800, hasRegularWidth: false, hasRegularHeight: true),
    Context(width: 1024, height: 300, hasRegularWidth: true, hasRegularHeight: true),
    Context(width: 1024, height: 800, hasRegularWidth: true, hasRegularHeight: true,
            usesAccessibilityTextSize: true),
  ] {
    #expect(CityChainLayoutPolicy().decide(context) == .singleColumn)
  }
}

@Test func keyboardDoesNotCollapseExpandedPanes() {
  // iPad landscape: the keyboard leaves ~300 pt, the resting window is ~690 pt.
  #expect(CityChainLayoutPolicy().decide(Context(
    width: 1024, height: 296, restingHeight: 690,
    hasRegularWidth: true, hasRegularHeight: true)) == .expandedPanes)
}

@Test(arguments: [319.0, 320])
func notebookAtlasUsesAtlasMinimumWidth(width: Double) {
  let fold = Context.Division(axis: .horizontal,
    before: .init(width: width, height: 400), after: .init(width: 400, height: 400))
  let result = CityChainLayoutPolicy().decide(Context(
    width: 400, height: 820, hasRegularWidth: true, hasRegularHeight: true, division: fold))
  #expect(result == (width >= 320 ? .foldAwareNotebook : .focusedAfterFold))
}

@Test func activeBookFoldTakesPriorityOverOrdinaryColumns() {
  let fold = Context.Division(axis: .vertical,
    before: .init(width: 360, height: 800), after: .init(width: 400, height: 800))
  #expect(CityChainLayoutPolicy().decide(Context(
    width: 780, height: 800, hasRegularWidth: true, hasRegularHeight: true,
    division: fold)) == .foldAwareBook)
}

@Test(arguments: [299.0, 300, 400])
func notebookGivesUpExplorationWhenKeyboardLeavesTooLittlePlaySpace(height: Double) {
  let fold = Context.Division(axis: .horizontal,
    before: .init(width: 740, height: 400), after: .init(width: 740, height: height))
  let result = CityChainLayoutPolicy().decide(Context(
    width: 740, height: 400 + height, hasRegularWidth: true, hasRegularHeight: true,
    division: fold))
  #expect(result == (height >= 300 ? .foldAwareNotebook : .focusedBeforeFold))
}

@Test func accessibilityKeepsGameInsideOneFoldRegion() {
  let fold = Context.Division(axis: .horizontal,
    before: .init(width: 740, height: 400), after: .init(width: 740, height: 400))
  #expect(CityChainLayoutPolicy().decide(Context(
    width: 740, height: 820, hasRegularWidth: true, hasRegularHeight: true,
    usesAccessibilityTextSize: true, division: fold)) == .focusedAfterFold)
}

@Test func narrowBookNeverFallsThroughToAnArrangementAcrossTheFold() {
  let fold = Context.Division(axis: .vertical,
    before: .init(width: 280, height: 700), after: .init(width: 440, height: 700))
  #expect(CityChainLayoutPolicy().decide(Context(
    width: 740, height: 700, hasRegularWidth: true, hasRegularHeight: true,
    division: fold)) == .focusedAfterFold)
}

@Test func atlasHistoryUsesPaneWidthAndAccessibility() {
  let rule = CityAtlasVerticalListSpec()
  #expect(!rule.isSatisfiedBy(.init(width: 319, usesAccessibilityTextSize: false)))
  #expect(rule.isSatisfiedBy(.init(width: 320, usesAccessibilityTextSize: false)))
  #expect(rule.isSatisfiedBy(.init(width: 280, usesAccessibilityTextSize: true)))
}

@Test func mapPresentationDoesNotChangeWhenKeyboardReducesHeight() {
  for height in [280.0, 800] {
    #expect(CityChainFullScreenMapSpec().isSatisfiedBy(Context(
      width: 1024, height: height, hasRegularWidth: true, hasRegularHeight: true)))
  }
}

@Test func scenicRouteYieldsToSharedAtlasOrConstrainedPlayArea() {
  let rule = CityChainScenicRouteSpec()
  #expect(rule.isSatisfiedBy(.init(plan: .singleColumn, gameHeight: 500, usesAccessibilityTextSize: false)))
  #expect(!rule.isSatisfiedBy(.init(plan: .singleColumn, gameHeight: 499, usesAccessibilityTextSize: false)))
  #expect(!rule.isSatisfiedBy(.init(plan: .expandedPanes, gameHeight: 800, usesAccessibilityTextSize: false)))
  #expect(!rule.isSatisfiedBy(.init(plan: .singleColumn, gameHeight: 800, usesAccessibilityTextSize: true)))
}
