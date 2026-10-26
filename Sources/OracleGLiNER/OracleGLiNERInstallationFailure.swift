import Foundation

/// Safe diagnostics: never retains file paths, response bodies or credentials.
public struct OracleGLiNERInstallationFailure: Error, Sendable, Equatable {
  public enum Stage: String, Sendable {
    case manifest, download, files, validation, runtime
  }
  public let stage: Stage
  public let domain: String
  public let code: Int

  public static func capture(_ error: any Error, stage: Stage) -> Self {
    if let failure = error as? Self { return failure }
    let issue = error as NSError
    return Self(stage: stage, domain: issue.domain, code: issue.code)
  }
}
