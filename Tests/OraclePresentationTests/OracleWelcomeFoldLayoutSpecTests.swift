import OraclePresentation
import Testing

@Test func welcomeSplitRequiresUsableRegions() {
  let policy = OracleWelcomeFoldLayoutSpec()
  let large = OracleWelcomeFoldContext.Region(width: 400, height: 300)
  let small = OracleWelcomeFoldContext.Region(width: 100, height: 100)
  #expect(policy.decide(.init(before: large, after: large)) == .split)
  #expect(policy.decide(.init(before: small, after: large)) == .after)
  #expect(policy.decide(.init(before: large, after: small)) == .before)
  #expect(policy.decide(.init(before: .init(width: .nan, height: 300), after: large)) == .after)
}
