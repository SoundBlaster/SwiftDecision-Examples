import SpecificationCore

/// Projects Core's diagnostic trace into the small set of events stored in history.
///
/// SpecificationCore currently accepts a concrete recorder per evaluation rather than a
/// pluggable event sink. Oracle therefore records into a short-lived Core recorder, then
/// keeps only these curated events in its persisted pipeline snapshot.
enum OraclePipelineTraceRecorder {
  private static let decisionEventNames: Set<String> = [
    "request validation",
    "policy routing",
    "backend prediction",
    "output validation",
    "minimum probability",
    "minimum confidence",
    "acceptance policy",
  ]

  /// Keep one semantic result for a game rule and discard its implementation tree.
  static func ruleResult(from events: [SpecificationTraceEvent]) -> [OracleSpecificationTraceStep] {
    let roots = events.filter { $0.parentID == nil }
    return roots.enumerated().map { index, event in
      OracleSpecificationTraceStep(
        id: index,
        parentID: nil,
        name: "Rule result",
        outcome: outcomeName(event.outcome),
        durationNanoseconds: event.durationNanoseconds
      )
    }
  }

  /// Keep named decision checkpoints and their nearest retained ancestors.
  static func decisionDetails(from events: [SpecificationTraceEvent]) -> [OracleSpecificationTraceStep] {
    let selected = events.filter { decisionEventNames.contains($0.name) }
    return details(from: selected, within: events)
  }

  /// Keep named answer-validation and resolution rules without exposing their erased wrapper tree.
  static func namedRuleDetails(
    from events: [SpecificationTraceEvent],
    names: Set<String>
  ) -> [OracleSpecificationTraceStep] {
    details(from: events.filter { names.contains($0.name) }, within: events)
  }

  private static func details(
    from selected: [SpecificationTraceEvent],
    within events: [SpecificationTraceEvent]
  ) -> [OracleSpecificationTraceStep] {
    let selectedIDs = Set(selected.map(\.id))
    let parents = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.parentID) })

    return selected.map { event in
      OracleSpecificationTraceStep(
        id: event.id,
        parentID: nearestSelectedAncestor(of: event.parentID, parents: parents, selectedIDs: selectedIDs),
        name: event.name,
        outcome: outcomeName(event.outcome),
        durationNanoseconds: event.durationNanoseconds
      )
    }
  }

  private static func nearestSelectedAncestor(
    of parentID: Int?,
    parents: [Int: Int?],
    selectedIDs: Set<Int>
  ) -> Int? {
    var parent = parentID
    var visited: Set<Int> = []
    while let id = parent, visited.insert(id).inserted {
      if selectedIDs.contains(id) {
        return id
      }
      parent = parents[id] ?? nil
    }
    return nil
  }

  private static func outcomeName(_ outcome: SpecificationTraceOutcome) -> String {
    switch outcome {
    case .satisfied: "Satisfied"
    case .unsatisfied: "Not satisfied"
    case .selected: "Selected"
    case .noMatch: "No match"
    case .skipped: "Skipped"
    case let .failed(errorType): "Failed: \(errorType)"
    case .cancelled: "Cancelled"
    }
  }
}
