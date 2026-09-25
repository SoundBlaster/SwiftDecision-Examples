import Foundation
import SpecificationCore

/// Produces one random Boolean outcome for any supplied context.
struct OracleRandomBooleanSpecification: Specification {
  private let generate: @Sendable () -> Bool

  init(generate: @escaping @Sendable () -> Bool = { Bool.random() }) {
    self.generate = generate
  }

  func isSatisfiedBy(_ candidate: Any) -> Bool {
    generate()
  }
}

struct OracleBooleanDistribution: Sendable, Hashable {
  let outcomes: [Bool]
  let trueCount: Int
  let falseCount: Int

  init(outcomes: [Bool]) {
    self.outcomes = outcomes
    trueCount = outcomes.filter { $0 }.count
    falseCount = outcomes.count - trueCount
  }

  var trueProbability: Double {
    Double(trueCount) / Double(outcomes.count)
  }

  var falseProbability: Double {
    Double(falseCount) / Double(outcomes.count)
  }

  var selectedValue: Bool? {
    guard trueCount != falseCount else { return nil }
    return trueCount > falseCount
  }
}

struct OracleRandomBooleanDistributionSpecification: DecisionSpec {
  static let sampleCount = 100

  private let generate: @Sendable () -> Bool

  init(generate: @escaping @Sendable () -> Bool = { Bool.random() }) {
    self.generate = generate
  }

  func decide(_ context: Any) -> OracleBooleanDistribution? {
    let sample = OracleRandomBooleanSpecification(generate: generate)
      .traced("Random Boolean sample")
    let outcomes = (0 ..< Self.sampleCount).map { _ in
      sample.isSatisfiedBy(context)
    }
    return OracleBooleanDistribution(outcomes: outcomes)
  }
}
