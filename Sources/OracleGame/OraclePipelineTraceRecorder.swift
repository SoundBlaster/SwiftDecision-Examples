import SpecificationCore
import SwiftDecision

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

  /// Preserves SwiftDecision's shared monotonic ordering while omitting erased implementation nodes.
  static func orderedDecisionTrace(
    from snapshot: DecisionTraceSnapshot
  ) -> [OraclePipelineTimelineEvent] {
    let specificationEvents = snapshot.records.compactMap { record -> SpecificationTraceEvent? in
      guard case let .specification(event) = record else { return nil }
      return event
    }
    let selected = specificationEvents.filter { decisionEventNames.contains($0.name) }
    let selectedIDs = Set(selected.map(\.id))
    let selectedByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
    let parents = Dictionary(uniqueKeysWithValues: specificationEvents.map { ($0.id, $0.parentID) })

    return snapshot.records.compactMap { record in
      switch record {
      case let .lifecycle(event):
        guard let position = record.position else { return nil }
        return OraclePipelineTimelineEvent(
          id: position.sequence,
          kind: .lifecycle,
          name: lifecycleName(event.stage),
          detail: event.detail ?? lifecycleExplanation(event.stage),
          elapsedNanoseconds: position.elapsedNanoseconds)

      case let .specification(event):
        guard decisionEventNames.contains(event.name),
              let position = event.startPosition
        else { return nil }
        let parent = nearestSelectedAncestor(
          of: event.parentID,
          parents: parents,
          selectedIDs: selectedIDs)
        return OraclePipelineTimelineEvent(
          id: position.sequence,
          parentID: parent.flatMap { selectedByID[$0]?.startPosition?.sequence },
          kind: .specification,
          name: event.name,
          outcome: outcomeName(event.outcome),
          durationNanoseconds: event.durationNanoseconds,
          elapsedNanoseconds: position.elapsedNanoseconds)
      }
    }
  }

  private static func lifecycleName(_ stage: DecisionTraceEvent.Stage) -> String {
    switch stage {
    case .requestValidated: "Request validated"
    case .policySelected: "Policy selected"
    case .inferenceStarted: "Inference started"
    case .inferenceCompleted: "Inference completed"
    case .outputValidated: "Output validated"
    case .resolved: "Decision resolved"
    }
  }

  private static func lifecycleExplanation(_ stage: DecisionTraceEvent.Stage) -> String? {
    switch stage {
    case .requestValidated:
      "ID and instructions are present; at least two options have descriptions and unique IDs."
    case .policySelected, .inferenceStarted, .inferenceCompleted, .outputValidated, .resolved:
      nil
    }
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
