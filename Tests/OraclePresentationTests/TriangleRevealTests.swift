import OraclePresentation
import Testing

@Test func revealApproachesWindowWithoutCrossingIt() {
  var previousZ: Float = 0
  var previousClarity: Float = 0
  for step in 0...140 {
    let frame = TriangleReveal.sample(elapsed: Double(step) / 100, reduceMotion: false)
    #expect(frame.position.z >= previousZ)
    #expect(frame.position.z < 0.854)
    #expect(frame.clarity >= previousClarity)
    #expect(frame.fogDistance > 0)
    previousZ = frame.position.z
    previousClarity = frame.clarity
  }
  #expect(TriangleReveal.sample(elapsed: 1.4, reduceMotion: false).clarity == 1)
}

@Test func reducedMotionKeepsGeometryStillWhileSurfaceAppears() {
  let start = TriangleReveal.sample(elapsed: 0, reduceMotion: true)
  let end = TriangleReveal.sample(elapsed: 3, reduceMotion: true)
  #expect(start.position == end.position)
  #expect(start.orientation.vector == end.orientation.vector)
  #expect(start.clarity == 0)
  #expect(end.clarity == 1)
  #expect(start.fogDistance > end.fogDistance)
}

@Test func negativeTimeMatchesTheHiddenFrame() {
  let negative = TriangleReveal.sample(elapsed: -5, reduceMotion: false)
  let zero = TriangleReveal.sample(elapsed: 0, reduceMotion: false)
  #expect(negative.position == zero.position)
  #expect(negative.clarity == zero.clarity)
}
