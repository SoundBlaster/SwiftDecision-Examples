import Foundation
import SwiftDecision

/// A failed request's safe category, provider and available pipeline, without an invented answer.
public struct OracleTracedFailure: Error, Sendable {
  public let kind: String
  public let mode: OracleMode
  public let provider: String
  public let pipeline: [OraclePipelineStage]

  public init(kind: String, mode: OracleMode, provider: String, pipeline: [OraclePipelineStage]) {
    self.kind = kind
    self.mode = mode
    self.provider = provider
    self.pipeline = pipeline
  }
}

/// One request owns this recorder, even when an engine serves concurrent requests.
final class OracleFailureTraceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: DecisionTraceSnapshot?

  func record(_ snapshot: DecisionTraceSnapshot) {
    lock.lock()
    defer { lock.unlock() }
    self.snapshot = snapshot
  }

  func latest() -> DecisionTraceSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return snapshot
  }
}
