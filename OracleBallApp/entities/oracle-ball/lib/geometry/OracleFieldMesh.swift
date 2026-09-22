import RealityKit
import simd

@MainActor
enum OracleFieldMesh {
  /// A flat annulus. UV.y runs across its width for the soft light profile.
  static func ring(halfWidth: Float) throws -> MeshResource {
    let segments = 128
    var positions: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    for segment in 0...segments {
      let u = Float(segment) / Float(segments)
      let angle = u * 2 * Float.pi
      let direction = SIMD2<Float>(cos(angle), sin(angle))
      for side in 0...1 {
        let radius = 1 + (side == 0 ? -halfWidth : halfWidth)
        positions.append([direction.x * radius, direction.y * radius, 0])
        uvs.append([u, Float(side)])
      }
    }

    for segment in 0..<segments {
      let a = UInt32(segment * 2)
      indices.append(contentsOf: [a, a + 1, a + 3, a, a + 3, a + 2])
    }
    return try mesh(positions: positions, uvs: uvs, indices: indices)
  }

  private static func mesh(
    positions: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt32]
  ) throws -> MeshResource {
    var descriptor = MeshDescriptor(name: "Oracle field ribbon")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 0, 1], count: positions.count))
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)
    return try MeshResource.generate(from: [descriptor])
  }
}
