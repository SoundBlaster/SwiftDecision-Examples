import SpecificationCore

/// Window facts measured by the UI, after safe areas and the keyboard are applied.
public struct OracleLayoutContext: Sendable {
  public struct Region: Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
      self.width = width.isFinite ? max(0, width) : 0
      self.height = height.isFinite ? max(0, height) : 0
    }
  }

  public struct Division: Sendable {
    public enum Axis: Sendable { case horizontal, vertical }
    public let axis: Axis
    public let before: Region
    public let after: Region

    public init(axis: Axis, before: Region, after: Region) {
      self.axis = axis
      self.before = before
      self.after = after
    }
  }

  public let viewport: Region
  public let restingHeight: Double
  public let hasRegularWidth: Bool
  public let usesAccessibilityTextSize: Bool
  public let division: Division?

  public init(
    width: Double, height: Double, restingHeight: Double,
    hasRegularWidth: Bool, usesAccessibilityTextSize: Bool,
    division: Division? = nil
  ) {
    viewport = Region(width: width, height: height)
    self.restingHeight = max(viewport.height, Region(width: width, height: restingHeight).height)
    self.hasRegularWidth = hasRegularWidth
    self.usesAccessibilityTextSize = usesAccessibilityTextSize
    self.division = division
  }
}

public enum OracleLayoutPlan: Sendable, Equatable {
  case singlePane, expandedPanes, book, tabletop
  /// Both children remain alive, within one usable side of an active fold.
  case focusedBeforeFold, focusedAfterFold

  public var supportsInlineHistory: Bool {
    switch self {
    case .expandedPanes, .book, .tabletop: true
    case .singlePane, .focusedBeforeFold, .focusedAfterFold: false
    }
  }
}

/// Chooses a layout from content fit, never from a device name or hinge angle.
public struct OracleLayoutPolicy: DecisionSpec {
  public static let minimumBallSide = 160.0
  public static let minimumControlsWidth = 280.0
  public static let minimumControlsHeight = 180.0
  public static let minimumExpandedWidth = 760.0

  public init() {}

  public func decide(_ context: OracleLayoutContext) -> OracleLayoutPlan? {
    let book = PredicateSpec<OracleLayoutContext>(description: "oracle.layout.book") {
      guard let fold = $0.division, fold.axis == .vertical else { return false }
      return fold.before.width >= Self.minimumBallSide
        && fold.before.height >= Self.minimumBallSide
        && fold.after.width >= Self.minimumControlsWidth
        && fold.after.height >= Self.minimumControlsHeight
    }
    let tabletop = PredicateSpec<OracleLayoutContext>(description: "oracle.layout.tabletop") {
      guard let fold = $0.division, fold.axis == .horizontal else { return false }
      return fold.before.width >= Self.minimumBallSide
        && fold.before.height >= Self.minimumBallSide
        && fold.after.width >= Self.minimumControlsWidth
        && fold.after.height >= Self.minimumControlsHeight
    }
    let focusedAfter = PredicateSpec<OracleLayoutContext>(description: "oracle.layout.focus-after-fold") {
      guard let fold = $0.division else { return false }
      if fold.after.width >= Self.minimumControlsWidth
        && fold.after.height >= Self.minimumControlsHeight { return true }
      return fold.after.width * fold.after.height >= fold.before.width * fold.before.height
    }
    let activeFold = PredicateSpec<OracleLayoutContext>(description: "oracle.layout.focus-before-fold") {
      $0.division != nil
    }
    let expanded = PredicateSpec<OracleLayoutContext>(description: "oracle.layout.expanded") {
      !$0.usesAccessibilityTextSize && $0.hasRegularWidth
        && $0.viewport.width >= Self.minimumExpandedWidth
        && $0.restingHeight >= 360
    }
    return FirstMatchSpec<OracleLayoutContext, OracleLayoutPlan>.withFallback([
      (book, .book), (tabletop, .tabletop),
      (focusedAfter, .focusedAfterFold), (activeFold, .focusedBeforeFold),
      (expanded, .expandedPanes),
    ], fallback: .singlePane).decide(context)
  }
}
