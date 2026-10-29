import CryptoKit
import Foundation
import Testing
@testable import OracleGame

@Suite("Local Oracle safety lexicon")
struct OracleSafetyLexiconTests {
  @Test func ranksRelevantExamplesAndRequiresMeaningfulOverlap() throws {
    let index = try OracleSafetyLexicon(packed: packed(#"{"version":1,"entries":[{"category":"ambiguousRisk","examples":["alpha beta"]},{"category":"dangerToLife","examples":["alpha beta gamma"]}]}"#))
    #expect(index.match("should alpha beta gamma?") == .dangerToLife)
    #expect(index.match("alpha unrelated") == nil)
    #expect(index.match("tea or coffee") == nil)
    #expect(OracleQuestionSafetySpec(lexicon: .success(index)).decide("alpha beta gamma") == .dangerToLife)
  }

  @Test func supportsRussianNormalizationAndExactSingleTermEntries() throws {
    let index = try OracleSafetyLexicon(packed: packed(#"{"version":1,"entries":[{"category":"selfHarm","examples":["ёлка снег"]},{"category":"harmToPeople","examples":["violet"]}]}"#))
    #expect(index.match("ЕЛКА, снег!") == .selfHarm)
    #expect(index.match("violet") == .harmToPeople)
    #expect(index.match("violets") == nil)
  }

  @Test func emptyLexiconPreservesExistingGuard() throws {
    let index = try OracleSafetyLexicon(packed: packed(#"{"version":1,"entries":[]}"#))
    let spec = OracleQuestionSafetySpec(lexicon: .success(index))
    #expect(spec.decide("Tea or coffee?") == nil)
    #expect(spec.decide("Should I kill myself?") == .selfHarm)
  }

  @Test func lexiconCanEscalateAnOtherwiseAmbiguousQuestion() throws {
    let index = try OracleSafetyLexicon(packed: packed(#"{"version":1,"entries":[{"category":"dangerToLife","examples":["jump"]}]}"#))
    #expect(OracleQuestionSafetySpec(lexicon: .success(index)).decide("Jump?") == .dangerToLife)
  }

  @Test func supportTakesPrecedenceOverAmbiguousMatches() throws {
    let index = try OracleSafetyLexicon(packed: packed(#"{"version":1,"entries":[{"category":"ambiguousRisk","examples":["alpha beta gamma"]},{"category":"dangerToLife","examples":["alpha beta"]}]}"#))
    #expect(index.match("alpha beta gamma") == .dangerToLife)
  }

  @Test func corruptedOrUnsupportedLexiconFailsClosed() throws {
    var corrupt = packed(#"{"version":1,"entries":[]}"#)
    corrupt[8] ^= 1
    #expect(throws: OracleSafetyLexicon.Error.self) { try OracleSafetyLexicon(packed: corrupt) }
    #expect(throws: OracleSafetyLexicon.Error.self) { try OracleSafetyLexicon(packed: packed(#"{"version":2,"entries":[]}"#)) }
    let spec = OracleQuestionSafetySpec(lexicon: .failure(.invalid))
    #expect(spec.decide("Tea or coffee?") == .filterUnavailable)
    #expect(spec.decide("Should I kill myself?") == .selfHarm)
    #expect(spec.decide("") == nil)
  }

  private func packed(_ value: String) -> Data {
    let bytes = Array(value.utf8)
    let length = UInt32(bytes.count)
    let header: [UInt8] = Array("OSL1".utf8) + [UInt8(truncatingIfNeeded: length >> 24),
      UInt8(truncatingIfNeeded: length >> 16), UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length)]
    return Data(header + Array(SHA256.hash(data: Data(bytes))) + bytes.enumerated().map {
      $0.element ^ UInt8(truncatingIfNeeded: $0.offset &* 53 &+ 167)
    })
  }
}
