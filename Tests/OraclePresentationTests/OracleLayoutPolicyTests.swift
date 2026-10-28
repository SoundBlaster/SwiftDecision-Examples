import OraclePresentation
import Testing

private typealias Context = OracleLayoutContext

private func context(_ division: Context.Division? = nil, width: Double = 800,
                     height: Double = 800, restingHeight: Double = 800,
                     regular: Bool = true, accessibility: Bool = false) -> Context {
  Context(width: width, height: height, restingHeight: restingHeight,
          hasRegularWidth: regular, usesAccessibilityTextSize: accessibility, division: division)
}

private func fold(_ axis: Context.Division.Axis, before: (Double, Double),
                  after: (Double, Double)) -> Context.Division {
  .init(axis: axis, before: .init(width: before.0, height: before.1),
        after: .init(width: after.0, height: after.1))
}

@Test func bookAndTabletopRespectTheActiveDivision() {
  let policy = OracleLayoutPolicy()
  #expect(policy.decide(context(fold(.vertical, before: (360, 700), after: (360, 700)))) == .book)
  #expect(policy.decide(context(fold(.horizontal, before: (700, 360), after: (700, 360)))) == .tabletop)
}

@Test func keyboardPrioritizesTheRegionThatFitsControls() {
  let policy = OracleLayoutPolicy()
  let keyboardFold = fold(.horizontal, before: (700, 360), after: (700, 100))
  #expect(policy.decide(context(keyboardFold, height: 460, restingHeight: 800)) == .focusedBeforeFold)
  let fittingAfter = fold(.horizontal, before: (700, 100), after: (700, 200))
  #expect(policy.decide(context(fittingAfter)) == .focusedAfterFold)
  let largerAfter = fold(.horizontal, before: (200, 100), after: (250, 100))
  #expect(policy.decide(context(largerAfter)) == .focusedAfterFold)
}

@Test func splitThresholdsAndFoldFallbackHaveExplicitBoundaries() {
  let policy = OracleLayoutPolicy()
  #expect(policy.decide(context(fold(.vertical, before: (159, 400), after: (280, 180)))) == .focusedAfterFold)
  #expect(policy.decide(context(fold(.vertical, before: (160, 400), after: (280, 180)))) == .book)
  #expect(policy.decide(context(fold(.vertical, before: (300, 400), after: (279, 179)))) == .focusedBeforeFold)
}

@Test func expandedRequiresSpaceAndRemainsStableWhileTyping() {
  let policy = OracleLayoutPolicy()
  #expect(policy.decide(context(width: 760, height: 300, restingHeight: 360)) == .expandedPanes)
  #expect(policy.decide(context(width: 759)) == .singlePane)
  #expect(policy.decide(context(width: 760, height: 359, restingHeight: 359)) == .singlePane)
  #expect(policy.decide(context(regular: false)) == .singlePane)
  #expect(policy.decide(context(accessibility: true)) == .singlePane)
}

@Test func inlineHistoryYieldsToKeyboardAccessibilityAndLimitedHeight() {
  let spec = OracleInlineHistorySpec()
  func allowed(_ plan: OracleLayoutPlan = .book, height: Double = 300,
               keyboard: Bool = false, accessibility: Bool = false) -> Bool {
    spec.isSatisfiedBy(.init(plan: plan, controlsHeight: height,
                             isKeyboardVisible: keyboard,
                             usesAccessibilityTextSize: accessibility))
  }
  #expect(allowed())
  #expect(!allowed(height: 299))
  #expect(!allowed(keyboard: true))
  #expect(!allowed(accessibility: true))
  #expect(!allowed(.singlePane))
  #expect(allowed(.tabletop))
}

@Test func ballVisibilityUsesAnExplicitMinimum() {
  let spec = OracleBallVisibilitySpec()
  #expect(!spec.isSatisfiedBy(99))
  #expect(spec.isSatisfiedBy(100))
  #expect(!spec.isSatisfiedBy(.infinity))
}
