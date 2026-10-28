import SpecificationCore

/// Inline history is secondary to the composer and remains accessible in settings.
public struct OracleInlineHistorySpec: Specification {
  public struct Context {
    public let plan: OracleLayoutPlan
    public let controlsHeight: Double
    public let isKeyboardVisible: Bool
    public let usesAccessibilityTextSize: Bool

    public init(plan: OracleLayoutPlan, controlsHeight: Double,
                isKeyboardVisible: Bool, usesAccessibilityTextSize: Bool) {
      self.plan = plan
      self.controlsHeight = controlsHeight
      self.isKeyboardVisible = isKeyboardVisible
      self.usesAccessibilityTextSize = usesAccessibilityTextSize
    }
  }

  /// Room for the composer, status, and the history card header.
  public static let minimumControlsHeight = 300.0
  public init() {}

  public func isSatisfiedBy(_ context: Context) -> Bool {
    context.plan.supportsInlineHistory && !context.isKeyboardVisible
      && !context.usesAccessibilityTextSize
      && context.controlsHeight >= Self.minimumControlsHeight
  }
}
