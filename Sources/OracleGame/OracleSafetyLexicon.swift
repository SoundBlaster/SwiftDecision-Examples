import CryptoKit
import Foundation

/// Local lexical retrieval. BM25 scores rank examples; they are not risk probabilities.
struct OracleSafetyLexicon: Sendable {
  enum Error: Swift.Error, Sendable { case invalid }

  private struct Document: Sendable {
    let category: OracleSafetyCategory
    let frequencies: [String: Int]
    let length: Int
  }

  private struct Payload: Decodable {
    struct Entry: Decodable {
      let category: String
      let examples: [String]
    }
    let version: Int
    let entries: [Entry]
  }

  private let documents: [Document]
  private let documentFrequency: [String: Int]
  private let averageLength: Double

  static func loadBundled() -> Result<Self, Error> {
    guard let url = Bundle.module.url(forResource: "OracleSafetyLexicon.private", withExtension: "bin") else {
      return .success(Self(documents: []))
    }
    do {
      return .success(try Self(packed: Data(contentsOf: url)))
    } catch {
      return .failure(.invalid)
    }
  }

  init(packed: Data) throws {
    let bytes = [UInt8](packed)
    guard bytes.count >= 40, bytes.count <= 1_048_616,
          Array(bytes[0..<4]) == Array("OSL1".utf8) else { throw Error.invalid }
    let length = bytes[4..<8].reduce(0) { ($0 << 8) | Int($1) }
    guard length <= 1_048_576, bytes.count == 40 + length else { throw Error.invalid }
    let decoded = Data(bytes[40...].enumerated().map { index, value in
      value ^ UInt8(truncatingIfNeeded: index &* 53 &+ 167)
    })
    guard Array(SHA256.hash(data: decoded)) == Array(bytes[8..<40]),
          let payload = try? JSONDecoder().decode(Payload.self, from: decoded),
          payload.version == 1, payload.entries.count <= 1_000 else { throw Error.invalid }
    var docs: [Document] = []
    for entry in payload.entries {
      let category: OracleSafetyCategory
      switch entry.category {
      case "selfHarm": category = .selfHarm
      case "harmToPeople": category = .harmToPeople
      case "dangerToLife": category = .dangerToLife
      case "ambiguousRisk": category = .ambiguousRisk
      default: throw Error.invalid
      }
      guard !entry.examples.isEmpty else { throw Error.invalid }
      for example in entry.examples {
        guard example.utf8.count <= 2_000 else { throw Error.invalid }
        let tokens = Self.tokens(example)
        guard !tokens.isEmpty, docs.count < 5_000 else { throw Error.invalid }
        docs.append(Document(category: category, frequencies: tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 },
                             length: tokens.count))
      }
    }
    self.init(documents: docs)
  }

  private init(documents: [Document]) {
    self.documents = documents
    var frequency: [String: Int] = [:]
    for document in documents {
      for term in document.frequencies.keys { frequency[term, default: 0] += 1 }
    }
    documentFrequency = frequency
    averageLength = documents.isEmpty ? 0 : Double(documents.reduce(0) { $0 + $1.length }) / Double(documents.count)
  }

  func match(_ question: String) -> OracleSafetyCategory? {
    let query = Set(Self.tokens(question))
    guard !query.isEmpty, averageLength > 0 else { return nil }
    var best: (score: Double, category: OracleSafetyCategory)?
    for document in documents {
      let terms = query.intersection(document.frequencies.keys)
      // Require most of the example's meaningful words, not just a common word.
      guard terms.count >= min(2, document.frequencies.count),
            Double(terms.count) / Double(document.frequencies.count) >= 0.75 else { continue }
      let score = terms.reduce(0.0) { sum, term in
        let df = Double(documentFrequency[term, default: 0])
        let idf = log(1 + (Double(documents.count) - df + 0.5) / (df + 0.5))
        let tf = Double(document.frequencies[term, default: 0])
        let denominator = tf + 1.2 * (1 - 0.75 + 0.75 * Double(document.length) / averageLength)
        return sum + idf * tf * 2.2 / denominator
      }
      if let current = best {
        let candidatePriority = document.category == .ambiguousRisk ? 0 : 1
        let currentPriority = current.category == .ambiguousRisk ? 0 : 1
        if candidatePriority < currentPriority || (candidatePriority == currentPriority && score <= current.score) {
          continue
        }
      }
      best = (score, document.category)
    }
    return best?.category
  }

  private static func tokens(_ text: String) -> [String] {
    let normalized = text.lowercased().replacingOccurrences(of: "ё", with: "е")
    let words = normalized.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
      .joined().split(whereSeparator: \.isWhitespace).map(String.init)
    let stopwords: Set<String> = ["a", "an", "and", "are", "at", "be", "do", "for", "from", "i", "is", "it",
                                  "my", "not", "of", "on", "or", "should", "the", "to", "will", "я", "ли",
                                  "или", "не", "мне", "как", "на", "с", "со", "в", "из", "от", "это", "за", "что", "а"]
    return words.filter { !stopwords.contains($0) }
  }
}
