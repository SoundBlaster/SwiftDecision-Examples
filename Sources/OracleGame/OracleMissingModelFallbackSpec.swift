import SpecificationCore

/// Allows the app to simulate an answer while its selected local model is absent.
/// Installed-but-failed models and loading requests retain their existing error handling.
public struct OracleMissingModelFallbackContext: Sendable {
  public let localModelSelected: Bool
  public let modelInstalled: Bool
  public let preparingModel: Bool

  public init(localModelSelected: Bool, modelInstalled: Bool, preparingModel: Bool) {
    self.localModelSelected = localModelSelected
    self.modelInstalled = modelInstalled
    self.preparingModel = preparingModel
  }
}

public struct OracleMissingModelFallbackSpec: Specification {
  public init() {}

  public func isSatisfiedBy(_ context: OracleMissingModelFallbackContext) -> Bool {
    context.localModelSelected && !context.modelInstalled && !context.preparingModel
  }
}
