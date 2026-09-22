import RealityKit
import simd

@MainActor
enum OracleMesh {
  private static let pi = Float.pi

  /// A unit sphere with its north cap removed for the oracle window.
  static func shell() throws -> MeshResource {
    let longitudeCount = 128
    let latitudeCount = 64
    // With z = sin(elevation), this puts the rim at xy radius 0.52.
    let firstLatitude = acos(Float(0.52))
    let lastLatitude = -pi / 2
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []

    for latitude in 0...latitudeCount {
      let t = Float(latitude) / Float(latitudeCount)
      let elevation = firstLatitude + (lastLatitude - firstLatitude) * t
      let radius = cos(elevation)
      for longitude in 0..<longitudeCount {
        let u = Float(longitude) / Float(longitudeCount)
        let angle = u * 2 * pi
        let normal = SIMD3<Float>(radius * cos(angle), radius * sin(angle), sin(elevation))
        positions.append(normal)
        normals.append(normal)
        uvs.append(SIMD2<Float>(u, t))
      }
    }

    var indices: [UInt32] = []
    for latitude in 0..<latitudeCount {
      for longitude in 0..<longitudeCount {
        let nextLongitude = (longitude + 1) % longitudeCount
        let a = UInt32(latitude * longitudeCount + longitude)
        let b = UInt32((latitude + 1) * longitudeCount + longitude)
        let c = UInt32((latitude + 1) * longitudeCount + nextLongitude)
        let d = UInt32(latitude * longitudeCount + nextLongitude)
        indices.append(contentsOf: [a, b, c, a, c, d])
      }
    }
    return try mesh(positions: positions, normals: normals, uvs: uvs, indices: indices)
  }

  /// A torus lying in the XY plane, with its outward normal along +Z at its crest.
  static func ring(radius: Float, tube: Float) throws -> MeshResource {
    let radialCount = 128
    let tubeCount = 24
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []

    for radial in 0..<radialCount {
      let u = Float(radial) / Float(radialCount)
      let radialAngle = u * 2 * pi
      for tubeIndex in 0..<tubeCount {
        let v = Float(tubeIndex) / Float(tubeCount)
        let tubeAngle = v * 2 * pi
        let cosTube = cos(tubeAngle)
        let sinTube = sin(tubeAngle)
        let ringRadius = radius + tube * cosTube
        positions.append(
          SIMD3<Float>(ringRadius * cos(radialAngle), ringRadius * sin(radialAngle), tube * sinTube)
        )
        normals.append(
          SIMD3<Float>(cosTube * cos(radialAngle), cosTube * sin(radialAngle), sinTube))
        uvs.append(SIMD2<Float>(u, v))
      }
    }

    var indices: [UInt32] = []
    for radial in 0..<radialCount {
      let nextRadial = (radial + 1) % radialCount
      for tubeIndex in 0..<tubeCount {
        let nextTube = (tubeIndex + 1) % tubeCount
        let a = UInt32(radial * tubeCount + tubeIndex)
        let b = UInt32(nextRadial * tubeCount + tubeIndex)
        let c = UInt32(nextRadial * tubeCount + nextTube)
        let d = UInt32(radial * tubeCount + nextTube)
        indices.append(contentsOf: [a, b, c, a, c, d])
      }
    }
    return try mesh(positions: positions, normals: normals, uvs: uvs, indices: indices)
  }

  /// A camera-facing disk for the soft shadow just beneath the window glass.
  static func windowDisk(radius: Float) throws -> MeshResource {
    let segments = 128
    var positions: [SIMD3<Float>] = [.zero]
    var uvs: [SIMD2<Float>] = [[0.5, 0.5]]
    var indices: [UInt32] = []
    for index in 0..<segments {
      let angle = Float(index) / Float(segments) * 2 * pi
      let point = SIMD2<Float>(cos(angle), sin(angle))
      positions.append([point.x * radius, point.y * radius, 0])
      uvs.append(point * 0.5 + SIMD2<Float>(repeating: 0.5))
      indices.append(contentsOf: [0, UInt32(index + 1), UInt32((index + 1) % segments + 1)])
    }
    return try mesh(
      positions: positions, normals: Array(repeating: [0, 0, 1], count: positions.count),
      uvs: uvs, indices: indices)
  }

  /// The front plate. Its UVs keep labels upright: the top edge is v == 0.
  static func triangle() throws -> MeshResource {
    let outline = roundedTriangleOutline()
    let positions = outline.map { SIMD3($0.x, $0.y, 0) }
    let normals = Array(repeating: SIMD3<Float>(0, 0, 1), count: positions.count)
    let uvs = outline.map { SIMD2(($0.x + 0.405) / 0.81, (0.235 - $0.y) / 0.665) }
    var indices: [UInt32] = []
    for index in 1..<(positions.count - 1) {
      // The outline is clockwise when viewed from +Z.
      indices.append(contentsOf: [0, UInt32(index + 1), UInt32(index)])
    }
    return try mesh(positions: positions, normals: normals, uvs: uvs, indices: indices)
  }

  /// The triangle's back and perimeter only; the caller can apply a separate side material.
  static func triangleSides() throws -> MeshResource {
    let frontZ: Float = 0
    let backZ: Float = -0.035
    let outline = roundedTriangleOutline()
    // Keep a separate copy per face so RealityKit does not smooth the prism edges.
    var positions: [SIMD3<Float>] = outline.map { SIMD3($0.x, $0.y, backZ) }
    var normals: [SIMD3<Float>] = Array(repeating: SIMD3<Float>(0, 0, -1), count: outline.count)
    var indices: [UInt32] = []
    for index in 1..<(outline.count - 1) {
      indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
    }
    for edge in outline.indices {
      let next = (edge + 1) % outline.count
      let start = outline[edge]
      let end = outline[next]
      let edgeVector = end - start
      let sideNormal2D = simd_normalize(SIMD2<Float>(-edgeVector.y, edgeVector.x))
      let base = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3(start.x, start.y, backZ), SIMD3(end.x, end.y, backZ),
        SIMD3(end.x, end.y, frontZ), SIMD3(start.x, start.y, frontZ),
      ])
      let sideNormal = SIMD3<Float>(sideNormal2D.x, sideNormal2D.y, 0)
      normals.append(contentsOf: [sideNormal, sideNormal, sideNormal, sideNormal])
      indices.append(contentsOf: [base, base + 2, base + 1, base, base + 3, base + 2])
    }
    return try mesh(positions: positions, normals: normals, indices: indices)
  }

  /// Returns a clockwise convex outline with approximately 0.02 radius corners.
  /// The same outline is used by the textured face and its solid perimeter.
  private static func roundedTriangleOutline() -> [SIMD2<Float>] {
    let corners: [SIMD2<Float>] = [
      SIMD2(-0.405, 0.235), SIMD2(0.405, 0.235), SIMD2(0, -0.43),
    ]
    let inset: Float = 0.035
    let samples = 7
    var outline: [SIMD2<Float>] = []
    for index in corners.indices {
      let previous = corners[(index + corners.count - 1) % corners.count]
      let corner = corners[index]
      let next = corners[(index + 1) % corners.count]
      let incoming = simd_normalize(previous - corner)
      let outgoing = simd_normalize(next - corner)
      let start = corner + incoming * inset
      let end = corner + outgoing * inset
      outline.append(start)
      for sample in 1...samples {
        let t = Float(sample) / Float(samples)
        let oneMinusT = 1 - t
        outline.append(oneMinusT * oneMinusT * start + 2 * oneMinusT * t * corner + t * t * end)
      }
    }
    return outline
  }

  private static func mesh(
    positions: [SIMD3<Float>],
    normals: [SIMD3<Float>],
    uvs: [SIMD2<Float>] = [],
    indices: [UInt32]
  ) throws -> MeshResource {
    var descriptor = MeshDescriptor()
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    if !uvs.isEmpty {
      descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    }
    descriptor.primitives = .triangles(indices)
    return try MeshResource.generate(from: [descriptor])
  }
}
