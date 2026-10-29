import SpecificationCore

/// Selects reduced welcome-screen spacing when the available window height is limited.
/// Height is the container's safe-area-adjusted height in points, before the footer inset.
public struct OracleWelcomeCompactLayoutSpec: Specification {
  public static let heightThreshold: Double = 700

  public init() {}

  public func isSatisfiedBy(_ height: Double) -> Bool {
    height.isFinite && height >= 0 && height < Self.heightThreshold
  }
}
