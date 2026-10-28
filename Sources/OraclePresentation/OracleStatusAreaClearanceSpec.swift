import SpecificationCore

/// Wide layouts leave vertical room below the side status area when possible.
public struct OracleStatusAreaClearanceSpec: Specification {
  public struct Context {
    public let plan: OracleLayoutPlan
    public let isKeyboardVisible: Bool

    public init(plan: OracleLayoutPlan, isKeyboardVisible: Bool) {
      self.plan = plan
      self.isKeyboardVisible = isKeyboardVisible
    }
  }

  public init() {}
  public func isSatisfiedBy(_ context: Context) -> Bool {
    (context.plan == .expandedPanes || context.plan == .book) && !context.isKeyboardVisible
  }
}
