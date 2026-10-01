import SpecificationCore

public struct CityChainLayoutContext: Sendable {
  public struct Region: Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
      self.width = width
      self.height = height
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
  /// Viewport height without the software keyboard. Arrangement-level choices
  /// (two panes, the full scenic route) use it so focusing the composer never
  /// rebuilds the screen; fold regions still use the keyboard-reduced space.
  public let restingHeight: Double
  public let hasRegularWidth: Bool
  public let hasRegularHeight: Bool
  public let usesAccessibilityTextSize: Bool
  public let division: Division?

  public init(
    width: Double, height: Double, restingHeight: Double? = nil,
    hasRegularWidth: Bool, hasRegularHeight: Bool,
    usesAccessibilityTextSize: Bool = false, division: Division? = nil
  ) {
    viewport = Region(width: width, height: height)
    self.restingHeight = max(restingHeight ?? height, height)
    self.hasRegularWidth = hasRegularWidth
    self.hasRegularHeight = hasRegularHeight
    self.usesAccessibilityTextSize = usesAccessibilityTextSize
    self.division = division
  }
}

public enum CityChainLayoutPlan: Equatable, Sendable {
  case singleColumn, expandedPanes, foldAwareBook, foldAwareNotebook
  /// Keep the game clear of an active fold when two panes cannot fit.
  case focusedBeforeFold, focusedAfterFold

  public var showsAtlas: Bool {
    switch self {
    case .expandedPanes, .foldAwareBook, .foldAwareNotebook: true
    case .singleColumn, .focusedBeforeFold, .focusedAfterFold: false
    }
  }
}

/// Layout policy takes already keyboard-adjusted, safe-area-adjusted dimensions.
/// Geometry, fold detection, focus, and game state remain in the UI adapter.
public struct CityChainLayoutPolicy: DecisionSpec {
  public static let minimumAtlasWidth = 320.0
  public static let minimumGameWidth = 340.0
  public static let columnInsets = 18.0
  public static let columnSpacing = 18.0
  public static let minimumExpandedWidth = minimumAtlasWidth + minimumGameWidth
    + columnInsets * 2 + columnSpacing
  public static let minimumExpandedHeight = 420.0
  public static let minimumNotebookAtlasHeight = 200.0
  public static let minimumPlayHeight = 300.0
  public static let minimumScenicRouteHeight = 500.0

  public init() {}

  public func decide(_ context: CityChainLayoutContext) -> CityChainLayoutPlan? {
    let book = PredicateSpec<CityChainLayoutContext>(description: "city.layout.book") {
      guard let division = $0.division, division.axis == .vertical else { return false }
      return !$0.usesAccessibilityTextSize
        && division.before.width >= Self.minimumAtlasWidth
        && division.after.width >= Self.minimumGameWidth
        && min(division.before.height, division.after.height) >= Self.minimumPlayHeight
    }
    let notebook = PredicateSpec<CityChainLayoutContext>(description: "city.layout.notebook") {
      guard let division = $0.division, division.axis == .horizontal else { return false }
      return !$0.usesAccessibilityTextSize
        && division.before.width >= Self.minimumAtlasWidth
        && division.after.width >= Self.minimumGameWidth
        && division.before.height >= Self.minimumNotebookAtlasHeight
        && division.after.height >= Self.minimumPlayHeight
    }
    let focusedAfter = PredicateSpec<CityChainLayoutContext>(description: "city.layout.focus-after-fold") {
      guard let division = $0.division else { return false }
      // Prefer the reachable lower/trailing region when readable. Otherwise use
      // the larger region, e.g. above a tabletop fold while the keyboard is up.
      return (division.after.width >= Self.minimumGameWidth
        && division.after.height >= Self.minimumPlayHeight)
        || division.after.width * division.after.height >= division.before.width * division.before.height
    }
    let activeFold = PredicateSpec<CityChainLayoutContext>(description: "city.layout.focus-before-fold") {
      $0.division != nil
    }
    let expanded = PredicateSpec<CityChainLayoutContext>(description: "city.layout.expanded") {
      !$0.usesAccessibilityTextSize && $0.hasRegularWidth && $0.hasRegularHeight
        && $0.viewport.width >= Self.minimumExpandedWidth
        && $0.restingHeight >= Self.minimumExpandedHeight
    }
    return FirstMatchSpec<CityChainLayoutContext, CityChainLayoutPlan>.withFallback([
      (book, .foldAwareBook),
      (notebook, .foldAwareNotebook),
      (focusedAfter, .focusedAfterFold),
      (activeFold, .focusedBeforeFold),
      (expanded, .expandedPanes),
    ], fallback: .singleColumn).decide(context)
  }
}

/// Atlas list policy is evaluated against its local pane, including Dynamic Type.
public struct CityAtlasVerticalListSpec: Specification {
  public struct Context: Sendable {
    public let width: Double
    public let usesAccessibilityTextSize: Bool
    public init(width: Double, usesAccessibilityTextSize: Bool) {
      self.width = width
      self.usesAccessibilityTextSize = usesAccessibilityTextSize
    }
  }

  public init() {}
  public func isSatisfiedBy(_ context: Context) -> Bool {
    context.width >= CityChainLayoutPolicy.minimumAtlasWidth || context.usesAccessibilityTextSize
  }
}

/// Presentation remains independent of fold layout and keyboard-reduced height.
public struct CityChainFullScreenMapSpec: Specification {
  public init() {}
  public func isSatisfiedBy(_ context: CityChainLayoutContext) -> Bool {
    context.hasRegularWidth && context.viewport.width >= CityChainLayoutPolicy.minimumExpandedWidth
  }
}

public struct CityChainScenicRouteSpec: Specification {
  public struct Context {
    public let plan: CityChainLayoutPlan
    public let gameHeight: Double
    public let usesAccessibilityTextSize: Bool
    public init(plan: CityChainLayoutPlan, gameHeight: Double, usesAccessibilityTextSize: Bool) {
      self.plan = plan
      self.gameHeight = gameHeight
      self.usesAccessibilityTextSize = usesAccessibilityTextSize
    }
  }

  public init() {}
  public func isSatisfiedBy(_ context: Context) -> Bool {
    context.plan == .singleColumn
      && context.gameHeight >= CityChainLayoutPolicy.minimumScenicRouteHeight
      && !context.usesAccessibilityTextSize
  }
}
