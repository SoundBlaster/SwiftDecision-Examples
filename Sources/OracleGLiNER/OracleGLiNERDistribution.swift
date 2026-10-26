import CryptoKit
import Foundation

/// A checked-in inventory pins the hosted content independently of its transport.
struct OracleGLiNERDistribution: Decodable {
  struct File: Decodable {
    let path: String
    let bytes: Int
    let sha256: String
  }
  let files: [File]

  func validate(directory: URL) throws {
    guard Set(files.map(\.path)).count == files.count else { throw OracleGLiNERModelError.invalidFolder }
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
      throw OracleGLiNERModelError.invalidFolder
    }
    var actual: Set<String> = []
    for case let relative as String in enumerator {
      let url = directory.appendingPathComponent(relative)
      if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        actual.insert(relative)
      }
    }
    actual.remove("distribution.json")
    guard actual == Set(files.map(\.path)) else { throw OracleGLiNERModelError.invalidFolder }
    for file in files {
      try Task.checkCancellation()
      guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else {
        throw OracleGLiNERModelError.invalidFolder
      }
      let url = directory.appendingPathComponent(file.path)
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == file.bytes else {
        throw OracleGLiNERModelError.invalidFolder
      }
      let digest = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
        .map { String(format: "%02x", $0) }.joined()
      guard digest == file.sha256 else { throw OracleGLiNERModelError.invalidFolder }
    }
  }
}
