#if SCREENER_SCREENSHOTS
import SpecificationCore

struct CityChainScreenshotReadinessContext {
  let hasSnapshot: Bool
  let isSubmitting: Bool
  let hasFixtureError: Bool
}

/// App-owned semantic readiness; the portable harness owns capture mechanics.
struct CityChainScreenshotReadinessSpec: Specification {
  func isSatisfiedBy(_ context: CityChainScreenshotReadinessContext) -> Bool {
    context.hasSnapshot && !context.isSubmitting && !context.hasFixtureError
  }
}
#endif
