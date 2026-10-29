import OraclePresentation
import Testing

@Test func welcomeCompactLayoutRespondsToAvailableHeight() {
  let spec = OracleWelcomeCompactLayoutSpec()
  #expect(spec.isSatisfiedBy(620))
  #expect(spec.isSatisfiedBy(699))
  #expect(!spec.isSatisfiedBy(700))
  #expect(!spec.isSatisfiedBy(800))
}

@Test func welcomeCompactLayoutRejectsInvalidMeasurements() {
  let spec = OracleWelcomeCompactLayoutSpec()
  #expect(!spec.isSatisfiedBy(-1))
  #expect(!spec.isSatisfiedBy(.nan))
  #expect(!spec.isSatisfiedBy(.infinity))
}
