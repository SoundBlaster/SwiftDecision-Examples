import SpecificationCore

/// A compact focused layout may still show the ball when it is smaller than
/// the minimum required for a comfortable split layout.
public struct OracleBallVisibilitySpec: Specification {
  public static let minimumVisibleSide = 100.0
  public init() {}
  public func isSatisfiedBy(_ availableSide: Double) -> Bool {
    availableSide.isFinite && availableSide >= Self.minimumVisibleSide
  }
}
