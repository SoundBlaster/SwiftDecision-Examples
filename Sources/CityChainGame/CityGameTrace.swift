import Foundation
import SpecificationCore
import SwiftDecision

/// One non-sensitive event in a City Chain turn.
public struct CityGameTraceEvent: Codable, Hashable, Identifiable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case specification
    case decision
  }

  public let id: String
  public let parentID: String?
  public let kind: Kind
  public let name: String
  public let detail: String?
  public let outcome: String?
  public let durationNanoseconds: UInt64?
  public let elapsedNanoseconds: UInt64?

  public init(
    id: String,
    parentID: String? = nil,
    kind: Kind,
    name: String,
    detail: String? = nil,
    outcome: String? = nil,
    durationNanoseconds: UInt64? = nil,
    elapsedNanoseconds: UInt64? = nil
  ) {
    self.id = id
    self.parentID = parentID
    self.kind = kind
    self.name = name
    self.detail = detail
    self.outcome = outcome
    self.durationNanoseconds = durationNanoseconds
    self.elapsedNanoseconds = elapsedNanoseconds
  }
}

/// A curated, user-facing summary of one stage in the City Chain engine.
public struct CityGamePipelineStage: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let summary: String?
  public let details: [CityGameTraceDetail]
  public let events: [CityGameTraceEvent]

  public init(
    id: String,
    title: String,
    summary: String? = nil,
    details: [CityGameTraceDetail] = [],
    events: [CityGameTraceEvent] = []
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.details = details
    self.events = events
  }
}

public struct CityGameTraceDetail: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let value: String

  public init(id: String, label: String, value: String) {
    self.id = id
    self.label = label
    self.value = value
  }
}

/// The ordinary turn result paired with its SpecificationCore and SwiftDecision trace.
public struct CityGameTracedTurnResult: Sendable {
  public let result: CityGameTurnResult
  public let pipeline: [CityGamePipelineStage]

  public init(result: CityGameTurnResult, pipeline: [CityGamePipelineStage]) {
    self.result = result
    self.pipeline = pipeline
  }
}

enum CityGameTraceProjection {
  static func specificationStage(
    id: String,
    title: String,
    summary: String? = nil,
    details: [CityGameTraceDetail] = [],
    events: [SpecificationTraceEvent]
  ) -> CityGamePipelineStage {
    CityGamePipelineStage(
      id: id,
      title: title,
      summary: summary,
      details: details,
      events: events.map { event in
        CityGameTraceEvent(
          id: "spec-\(event.id)",
          parentID: event.parentID.map { "spec-\($0)" },
          kind: .specification,
          name: event.name,
          outcome: outcomeName(event.outcome),
          durationNanoseconds: event.durationNanoseconds,
          elapsedNanoseconds: event.startPosition?.elapsedNanoseconds)
      })
  }

  static func decisionStage<Value: Sendable>(
    id: String,
    title: String,
    summary: String? = nil,
    details: [CityGameTraceDetail] = [],
    result: DecisionResult<Value>
  ) -> CityGamePipelineStage {
    let snapshot = result.orderedTrace
    let specificationRecords = snapshot.records.compactMap { record -> SpecificationTraceEvent? in
      guard case .specification(let event) = record else { return nil }
      return event
    }
    let eventIDsBySpecificationID = Dictionary(
      uniqueKeysWithValues: specificationRecords.compactMap { event in
        event.startPosition.map { (event.id, "decision-\($0.sequence)") }
      })

    let events = snapshot.records.compactMap { record -> CityGameTraceEvent? in
      switch record {
      case .lifecycle(let event):
        return CityGameTraceEvent(
          id: "decision-\(event.position.sequence)",
          kind: .decision,
          name: event.stage.rawValue,
          detail: event.detail,
          elapsedNanoseconds: event.position.elapsedNanoseconds)

      case .specification(let event):
        let id = event.startPosition.map { "decision-\($0.sequence)" } ?? "spec-\(event.id)"
        return CityGameTraceEvent(
          id: id,
          parentID: event.parentID.flatMap { eventIDsBySpecificationID[$0] },
          kind: .specification,
          name: event.name,
          outcome: outcomeName(event.outcome),
          durationNanoseconds: event.durationNanoseconds,
          elapsedNanoseconds: event.startPosition?.elapsedNanoseconds)
      }
    }

    return CityGamePipelineStage(
      id: id,
      title: title,
      summary: summary,
      details: details,
      events: events.sorted {
        ($0.elapsedNanoseconds ?? UInt64.max) < ($1.elapsedNanoseconds ?? UInt64.max)
      })
  }

  static func stage(
    id: String,
    title: String,
    summary: String? = nil,
    details: [CityGameTraceDetail] = []
  ) -> CityGamePipelineStage {
    CityGamePipelineStage(id: id, title: title, summary: summary, details: details)
  }

  private static func outcomeName(_ outcome: SpecificationTraceOutcome) -> String {
    switch outcome {
    case .satisfied: "Satisfied"
    case .unsatisfied: "Not satisfied"
    case .selected: "Selected"
    case .noMatch: "No match"
    case .skipped: "Skipped"
    case .failed(let typeName): "Failed (\(typeName))"
    case .cancelled: "Cancelled"
    }
  }
}
