import SpecificationCore

/// Usable areas on either side of an active screen division, in points.
public struct OracleWelcomeFoldContext: Sendable {
  public struct Region: Sendable {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) {
      self.width = width.isFinite ? max(0, width) : 0
      self.height = height.isFinite ? max(0, height) : 0
    }
  }
  public let before: Region
  public let after: Region
  public init(before: Region, after: Region) {
    self.before = before
    self.after = after
  }
}

public enum OracleWelcomeFoldPlan: Equatable, Sendable {
  case split, before, after
}

/// Keeps both panes off the fold, or falls back to the larger usable region.
public struct OracleWelcomeFoldLayoutSpec: DecisionSpec {
  public init() {}

  public func decide(_ context: OracleWelcomeFoldContext) -> OracleWelcomeFoldPlan? {
    let before = context.before
    let after = context.after
    if before.width >= 240 && before.height >= 180
      && after.width >= 240 && after.height >= 180 {
      return .split
    }
    return after.width * after.height >= before.width * before.height ? .after : .before
  }
}
