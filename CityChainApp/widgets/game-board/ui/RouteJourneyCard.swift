import CityChainGame
import SwiftUI

/// Transient animation state. The game snapshot remains the source of truth.
private struct RouteJourneyState {
  enum Phase {
    case waiting
    case revealing
    case travelling
  }

  private(set) var receivedRoute: [USCity]?
  private(set) var currentCity: USCity?
  private(set) var incomingCity: USCity?
  private(set) var phase = Phase.waiting
  private(set) var animationID: UUID?
  private var pendingCities: [USCity] = []

  /// Restores/replaces routes immediately; queues only newly accepted turns.
  mutating func receive(_ route: [USCity]) -> Bool {
    guard let previous = receivedRoute, route.starts(with: previous) else {
      settle(on: route)
      return true
    }
    pendingCities.append(contentsOf: route.dropFirst(previous.count))
    receivedRoute = route
    return false
  }

  mutating func settle(on route: [USCity]) {
    receivedRoute = route
    currentCity = route.last
    incomingCity = nil
    pendingCities = []
    phase = .waiting
    animationID = nil
  }

  mutating func beginNextLeg() -> UUID? {
    guard phase == .waiting, !pendingCities.isEmpty else { return nil }
    incomingCity = pendingCities.removeFirst()
    phase = .revealing
    let id = UUID()
    animationID = id
    return id
  }

  mutating func startTravelling(id: UUID) -> Bool {
    guard animationID == id, phase == .revealing else { return false }
    phase = .travelling
    return true
  }

  mutating func arrive(id: UUID) -> Bool {
    guard animationID == id, phase == .travelling else { return false }
    currentCity = incomingCity
    incomingCity = nil
    phase = .waiting
    animationID = nil
    return true
  }
}

/// An illustrated invitation before the first complete leg of the trip.
struct EmptyRouteCard: View {
  var body: some View {
    ViewThatFits(in: .horizontal) {
      content(isWide: true)
        .frame(minWidth: 560)
      content(isWide: false)
    }
    .background(.white)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(CityChainPalette.ink.opacity(0.06), lineWidth: 1)
    }
    .shadow(color: CityChainPalette.ink.opacity(0.04), radius: 12, y: 5)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("cityChain.home.emptyRoute")
  }

  private func content(isWide: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Your route")
        .font(.system(isWide ? .title3 : .headline, design: .rounded, weight: .heavy))
        .foregroundStyle(CityChainPalette.ink)
        .padding(.leading, isWide ? 14 : 8)
        .padding(.trailing, 48)
        .padding(.bottom, 8)

      VStack(alignment: .leading, spacing: 3) {
        endpointTitle("Start")
        endpointSubtitle("Choose a city")
      }

      GeometryReader { geometry in
        let start = CGPoint(x: 13, y: 13)
        let middle = CGPoint(x: geometry.size.width * 0.50, y: geometry.size.height * 0.50)
        let finish = CGPoint(x: geometry.size.width - 13, y: geometry.size.height - 13)
        ZStack {
          RoutePlaceholderTrailScenery()
          Path { path in
            path.move(to: start)
            path.addCurve(
              to: middle,
              control1: CGPoint(x: geometry.size.width * 0.42, y: start.y),
              control2: CGPoint(x: geometry.size.width * 0.28, y: middle.y))
            path.addCurve(
              to: finish,
              control1: CGPoint(x: geometry.size.width * 0.80, y: middle.y),
              control2: CGPoint(x: geometry.size.width * 0.86, y: finish.y))
          }
          .stroke(
            CityChainPalette.blue.opacity(0.55),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 7]))
          endpointDot.position(start)
          ZStack {
            endpointDot
            Text("?")
              .font(.system(size: 12, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
          }
          .position(finish)
          Image(systemName: "car.side.fill")
            .font(.system(size: 20))
            .foregroundStyle(CityChainPalette.teal)
            .scaleEffect(x: -1, y: 1)
            .padding(.horizontal, 3)
            .background(.white, in: Capsule())
            .position(middle)
        }
      }
      .frame(height: isWide ? 100 : 120)
      .accessibilityHidden(true)

      VStack(alignment: .trailing, spacing: 3) {
        endpointTitle("Next")
        endpointSubtitle("Keep going")
      }
      .padding(.leading, isWide ? 160 : 120)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(alignment: .bottomLeading) {
      RoutePlaceholderLandscape()
        .frame(width: isWide ? 240 : 156, height: isWide ? 94 : 86)
        .offset(x: isWide ? -18 : -12, y: isWide ? 12 : 10)
        .accessibilityHidden(true)
    }
    .background(alignment: .topTrailing) {
      RoutePlaceholderCloud()
        .fill(Color(red: 0.85, green: 0.94, blue: 0.98).gradient)
        .frame(width: isWide ? 46 : 34, height: isWide ? 22 : 16)
        .padding(.trailing, 64)
        .padding(.top, 24)
        .accessibilityHidden(true)
    }
  }

  private func endpointTitle(_ title: LocalizedStringKey) -> some View {
    Text(title)
      .font(.system(.subheadline, design: .rounded, weight: .bold))
      .foregroundStyle(CityChainPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func endpointSubtitle(_ subtitle: LocalizedStringKey) -> some View {
    Text(subtitle)
      .font(.caption)
      .foregroundStyle(CityChainPalette.secondaryInk)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var endpointDot: some View {
    Circle()
      .fill(CityChainPalette.blue.gradient)
      .frame(width: 20, height: 20)
      .padding(5)
      .background(Color(red: 0.91, green: 0.95, blue: 1), in: Circle())
      .accessibilityHidden(true)
  }
}

private struct RoutePlaceholderTrailScenery: View {
  var body: some View {
    Canvas { context, size in
      let lake = CGRect(x: size.width * 0.22, y: size.height * 0.52,
                        width: size.width * 0.23, height: size.height * 0.22)
      context.fill(Path(ellipseIn: lake), with: .color(Color(red: 0.80, green: 0.93, blue: 0.98)))
      context.fill(Path(ellipseIn: lake.offsetBy(dx: lake.width * 0.20, dy: lake.height * 0.32)),
                   with: .color(Color(red: 0.80, green: 0.93, blue: 0.98)))
      for index in 0..<2 {
        let x = lake.midX + CGFloat(index) * 8
        let y = lake.midY + CGFloat(index) * 7
        var wave = Path()
        wave.move(to: CGPoint(x: x - 8, y: y))
        wave.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 4, y: y - 5))
        wave.addQuadCurve(to: CGPoint(x: x + 8, y: y), control: CGPoint(x: x + 4, y: y + 5))
        context.stroke(wave, with: .color(Color(red: 0.43, green: 0.73, blue: 0.83)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
      }
      for (x, y) in [(0.13, 0.42), (0.60, 0.86), (0.74, 0.25)] {
        let center = CGPoint(x: size.width * x, y: size.height * y)
        var grass = Path()
        for offset in [-4.0, 0, 4.0] {
          grass.move(to: center)
          grass.addLine(to: CGPoint(x: center.x + offset, y: center.y - 6 + abs(offset) * 0.4))
        }
        context.stroke(grass, with: .color(Color(red: 0.54, green: 0.70, blue: 0.44).opacity(0.6)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
      }
    }
    .overlay(alignment: .topTrailing) {
      RoutePlaceholderLandscape()
        .frame(width: 80, height: 46)
        .padding(.trailing, 34)
        .opacity(0.7)
    }
    .allowsHitTesting(false)
  }
}

struct RoutePlaceholderCloud: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addCurve(
        to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.42),
        control1: CGPoint(x: rect.minX, y: rect.height * 0.48),
        control2: CGPoint(x: rect.width * 0.10, y: rect.height * 0.28))
      path.addCurve(
        to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.42),
        control1: CGPoint(x: rect.width * 0.32, y: -rect.height * 0.14),
        control2: CGPoint(x: rect.width * 0.64, y: -rect.height * 0.14))
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.maxY),
        control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.28),
        control2: CGPoint(x: rect.maxX, y: rect.height * 0.48))
      path.closeSubpath()
    }
  }
}

struct RoutePlaceholderLandscape: View {
  var body: some View {
    Canvas { context, size in
      for (x, height, width) in [(0.40, 0.97, 0.80), (0.77, 0.60, 0.64)] {
        var mountain = Path()
        mountain.move(to: CGPoint(x: size.width * (x - width / 2), y: size.height))
        mountain.addQuadCurve(
          to: CGPoint(x: size.width * x, y: size.height * (1 - height)),
          control: CGPoint(x: size.width * (x - width * 0.12), y: size.height * (1 - height)))
        mountain.addQuadCurve(
          to: CGPoint(x: size.width * (x + width / 2), y: size.height),
          control: CGPoint(x: size.width * (x + width * 0.12), y: size.height * (1 - height)))
        mountain.closeSubpath()
        context.fill(mountain, with: .linearGradient(
          Gradient(colors: [Color(red: 0.83, green: 0.94, blue: 0.98),
                            Color(red: 0.68, green: 0.85, blue: 0.91)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
      }
      for (x, height) in [(0.10, 0.74), (0.39, 0.50), (0.64, 0.35)] {
        for layer in 0..<3 {
          let top = size.height * (1 - height + Double(layer) * height * 0.19)
          let halfWidth = size.width * height * (0.15 + Double(layer) * 0.035)
          var tree = Path()
          tree.move(to: CGPoint(x: size.width * x, y: top))
          tree.addLine(to: CGPoint(x: size.width * x - halfWidth, y: top + size.height * height * 0.45))
          tree.addLine(to: CGPoint(x: size.width * x + halfWidth, y: top + size.height * height * 0.45))
          tree.closeSubpath()
          context.fill(tree, with: .color(Color(red: 0.25, green: 0.57, blue: 0.46).opacity(0.85)))
        }
      }
    }
    .allowsHitTesting(false)
  }
}

struct RoutePlaceholderCompass: View {
  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = size.width * 0.25
      let ink = CityChainPalette.secondaryInk.opacity(0.55)
      context.stroke(Path(ellipseIn: CGRect(
        x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2)), with: .color(ink), lineWidth: 1)
      for index in 0..<4 {
        let angle = Double(index) * .pi / 2
        var needle = Path()
        needle.move(to: CGPoint(x: center.x + cos(angle) * radius * 1.25,
                               y: center.y + sin(angle) * radius * 1.25))
        needle.addLine(to: CGPoint(x: center.x - sin(angle) * 3, y: center.y + cos(angle) * 3))
        needle.addLine(to: center)
        needle.closeSubpath()
        context.fill(needle, with: .color(ink))
      }
      for (title, x, y) in [("N", 0.5, 0.06), ("E", 0.94, 0.5), ("S", 0.5, 0.94), ("W", 0.06, 0.5)] {
        context.draw(Text(verbatim: title).font(.system(size: 7, weight: .bold)).foregroundStyle(ink),
                     at: CGPoint(x: size.width * x, y: size.height * y))
      }
    }
  }
}


/// Shows the latest accepted stop and the unknown next stop.
/// Each newly appended player/Scout city travels from right to left in order.
struct RouteJourneyCard: View {
  let cities: [USCity]?
  let isWaitingForScout: Bool
  var appearance: RouteJourneyAppearance = .classic
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var journey = RouteJourneyState()
  @State private var progress: CGFloat = 0
  @State private var reveal: Double = 0

  var body: some View {
    ZStack {
      if journey.currentCity == nil && journey.incomingCity == nil {
        if appearance == .scenic {
          ScenicEmptyRouteCard()
        } else {
          EmptyRouteCard()
        }
      } else if appearance == .scenic {
        ScenicRouteJourneyCanvas(
          currentCity: journey.currentCity,
          incomingCity: journey.incomingCity,
          progress: progress,
          reveal: reveal,
          isDriving: journey.phase != .waiting || isWaitingForScout)
      } else {
        RouteJourneyCanvas(
          currentCity: journey.currentCity,
          incomingCity: journey.incomingCity,
          progress: progress, reveal: reveal,
          isDriving: journey.phase != .waiting || isWaitingForScout)
      }
    }
    .onChange(of: cities, initial: true) { _, route in
      guard let route else { return }
      if journey.receive(route) || reduceMotion || scenePhase != .active {
        settle(on: route)
      } else {
        beginNextLeg()
      }
    }
    .onChange(of: reduceMotion) { _, reduced in
      if reduced, let cities { settle(on: cities) }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active, let cities { settle(on: cities) }
    }
    .onDisappear {
      if let cities { settle(on: cities) }
    }
  }

  private func settle(on route: [USCity]) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      journey.settle(on: route)
      progress = 0
      reveal = 0
    }
  }

  private func beginNextLeg() {
    guard let id = journey.beginNextLeg() else { return }
    // First reveal the accepted name at the unknown destination.
    withAnimation(.easeInOut(duration: 0.22), completionCriteria: .removed) {
      reveal = 1
    } completion: {
      guard journey.startTravelling(id: id) else { return }
      withAnimation(.smooth(duration: 1.0), completionCriteria: .removed) {
        progress = 1
      } completion: {
        guard journey.animationID == id else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          _ = journey.arrive(id: id)
          progress = 0
          reveal = 0
        }
        beginNextLeg()
      }
    }
  }
}

enum RouteJourneyAppearance {
  case classic
  case scenic
}

/// Separate copy of the route card using the illustrated atlas treatment.
struct ScenicRouteJourneyCard: View {
  let cities: [USCity]?
  let isWaitingForScout: Bool

  var body: some View {
    RouteJourneyCard(cities: cities, isWaitingForScout: isWaitingForScout, appearance: .scenic)
  }
}

private struct ScenicEmptyRouteCard: View {
  var body: some View {
    ScenicRouteJourneyCanvas(
      currentCity: nil,
      incomingCity: nil,
      progress: 0,
      reveal: 0,
      isDriving: false)
  }
}

/// Illustrated route card. Everything is placed in unit coordinates of the card,
/// so the composition keeps the mockup's balance from narrow phones to iPad.
private struct ScenicRouteJourneyCanvas: View {
  let currentCity: USCity?
  let incomingCity: USCity?
  let progress: CGFloat
  let reveal: Double
  let isDriving: Bool

  var body: some View {
    ScenicCardLayout {
      GeometryReader { geometry in
        let size = geometry.size
        ZStack(alignment: .topLeading) {
          ZStack {
            ScenicRouteScenery(size: size)
            ScenicRouteLayer(
              route: ScenicRoute(size: size),
              currentCity: currentCity,
              incomingCity: incomingCity,
              progress: progress,
              reveal: reveal,
              isDriving: isDriving)
          }
          .frame(width: size.width, height: size.height)
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(accessibleRoute)

          Text("Your route")
            .font(.system(.title2, design: .rounded, weight: .black))
            .foregroundStyle(CityChainPalette.ink)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, 18)
            .padding(.top, 14)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .background(.white, in: RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(CityChainPalette.ink.opacity(0.06), lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .shadow(color: CityChainPalette.ink.opacity(0.04), radius: 12, y: 5)
  }

  private var accessibleRoute: String {
    if let incomingCity, let currentCity {
      return String(localized: "Travelling from \(currentCity.name) to \(incomingCity.name)")
    } else if let incomingCity {
      return String(localized: "First stop: \(incomingCity.name)")
    } else if let currentCity {
      return String(localized: "Current city: \(currentCity.name). Next city is a surprise.")
    }
    return String(localized: "Choose your first city.")
  }
}

/// Keeps the illustration close to the mockup's proportions without letting it grow too tall.
private struct ScenicCardLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let proposed = proposal.width ?? 350
    let width = proposed.isFinite ? proposed : 350
    return CGSize(width: width, height: min(max(width / 1.46, 220), 290))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
  }
}

/// Two cubic legs: down from the start, across the lake, then down to the next stop.
/// Positions are measured along the thread, so beads keep equal spacing as they slide.
private struct ScenicRoute {
  let size: CGSize
  let start: CGPoint
  let finish: CGPoint
  /// Arc length of the visible thread.
  let length: CGFloat
  private let bend: CGPoint
  private let controls: [CGPoint]
  private let samples: [CGPoint]
  private let distances: [CGFloat]

  init(size: CGSize) {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: size.width * x, y: size.height * y)
    }
    self.size = size
    start = point(0.10, 0.27)
    bend = point(0.45, 0.49)
    finish = point(0.84, 0.755)
    controls = [point(0.11, 0.45), point(0.30, 0.40), point(0.56, 0.59), point(0.76, 0.55)]

    let (start, bend, finish, controls) = (start, bend, finish, controls)
    let samples = (0...96).map { index in
      let t = CGFloat(index) / 96
      return t <= 0.5
        ? Self.cubic(start, controls[0], controls[1], bend, t * 2)
        : Self.cubic(bend, controls[2], controls[3], finish, t * 2 - 1)
    }
    var total: CGFloat = 0
    var distances: [CGFloat] = [0]
    for (a, b) in zip(samples, samples.dropFirst()) {
      total += Self.distance(a, b)
      distances.append(total)
    }
    self.samples = samples
    self.distances = distances
    length = total
  }

  var path: Path {
    Path { path in
      path.move(to: start)
      path.addCurve(to: bend, control1: controls[0], control2: controls[1])
      path.addCurve(to: finish, control1: controls[2], control2: controls[3])
    }
  }

  /// 0 is the start stop, 1 is the next stop. Values outside continue the thread past
  /// its ends so beads can slide in and out of view: off the left edge before the start
  /// (clear of the title), along the final tangent after the finish.
  func point(at position: CGFloat) -> CGPoint {
    let target = position * length
    if target <= 0 {
      return CGPoint(x: start.x + target, y: start.y)
    }
    if target >= length {
      return Self.moved(finish, awayFrom: controls[3], by: target - length)
    }
    let upper = distances.firstIndex { $0 >= target } ?? distances.count - 1
    let lower = max(upper - 1, 0)
    let span = distances[upper] - distances[lower]
    let fraction = span > 0 ? (target - distances[lower]) / span : 0
    let (a, b) = (samples[lower], samples[upper])
    return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
  }

  /// How far past either end of the thread a position lies, in points.
  func overshoot(at position: CGFloat) -> CGFloat {
    max(-position, position - 1, 0) * length
  }

  private static func moved(_ point: CGPoint, awayFrom source: CGPoint, by offset: CGFloat) -> CGPoint {
    let span = max(distance(point, source), 1)
    return CGPoint(
      x: point.x + (point.x - source.x) / span * offset,
      y: point.y + (point.y - source.y) / span * offset)
  }

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(b.x - a.x, b.y - a.y)
  }

  private static func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let (wa, wb, wc, wd) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
    return CGPoint(
      x: wa * a.x + wb * b.x + wc * c.x + wd * d.x,
      y: wa * a.y + wb * b.y + wc * c.y + wd * d.y)
  }
}

private struct ScenicRouteScenery: View {
  let size: CGSize

  var body: some View {
    ZStack {
      decoration("RouteHills", x: 0.20, y: 0.82, width: 0.48, height: 0.44, keepsAspect: false)
      decoration("RouteTrees", x: 0.14, y: 0.92, width: 0.30, height: 0.34)
      decoration("RouteMountains", x: 0.603, y: 0.275, width: 0.26, height: 0.19)
      decoration("RouteTrees", x: 0.468, y: 0.34, width: 0.12, height: 0.17)
      decoration("RouteLake", x: 0.376, y: 0.583, width: 0.25, height: 0.14)
      decoration("RouteTrees", x: 0.655, y: 0.814, width: 0.14, height: 0.16)
      decoration("RouteGrass", x: 0.125, y: 0.47, width: 0.045, height: 0.07)
      decoration("RouteGrass", x: 0.643, y: 0.461, width: 0.045, height: 0.07)
      decoration("RouteGrass", x: 0.522, y: 0.706, width: 0.045, height: 0.07)
      decoration("RouteCompass", x: 0.887, y: 0.141,
                 width: min(0.14, 0.19 * size.height / size.width), height: 0.19)
      tagline
    }
    .frame(width: size.width, height: size.height)
    .accessibilityHidden(true)
  }

  private func decoration(
    _ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, keepsAspect: Bool = true
  ) -> some View {
    Image(name)
      .resizable()
      // A nil ratio keeps the artwork's own; the frame's ratio stretches it to fill.
      .aspectRatio(keepsAspect ? nil : (width * size.width) / (height * size.height), contentMode: .fit)
      .frame(width: size.width * width, height: size.height * height)
      .position(x: size.width * x, y: size.height * y)
  }

  private var tagline: some View {
    VStack(alignment: .trailing, spacing: -3) {
      Text("Small cities.\nBig stories.")
        .font(.custom("Noteworthy-Light", size: 15, relativeTo: .footnote))
        .foregroundStyle(CityChainPalette.secondaryInk)
        .multilineTextAlignment(.trailing)
        .lineSpacing(-2)
        .fixedSize()
      TaglineSwoosh()
        .stroke(CityChainPalette.blue.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .frame(width: 58, height: 8)
    }
    .rotationEffect(.degrees(-14))
    .position(x: size.width * 0.855, y: size.height * 0.44)
  }
}

private struct TaglineSwoosh: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY),
        control: CGPoint(x: rect.width * 0.45, y: rect.maxY))
    }
  }
}

/// Stops threaded like beads on the dashed route. Each accepted city pulls the whole
/// thread one stop towards the start: the current stop slides out past the start,
/// the next stop takes its place, and a fresh "Next" slides in from past the finish.
/// Animatable so every bead follows the curve frame by frame.
private struct ScenicRouteLayer: View, Animatable {
  let route: ScenicRoute
  let currentCity: USCity?
  let incomingCity: USCity?
  var progress: CGFloat
  var reveal: Double
  let isDriving: Bool

  /// Beads fade out over this distance past either end of the thread.
  private let fadeDistance: CGFloat = 30

  nonisolated var animatableData: AnimatablePair<CGFloat, Double> {
    get { AnimatablePair(progress, reveal) }
    set { (progress, reveal) = (newValue.first, newValue.second) }
  }

  var body: some View {
    let shift = incomingCity == nil ? 0 : progress
    let leaving = route.point(at: -shift)
    let arriving = route.point(at: 1 - shift)
    let captionOut = Double(max(0, 1 - shift * 4))
    let captionIn = Double(max(0, shift * 4 - 3))

    ZStack {
      route.path
        .stroke(
          CityChainPalette.blue.opacity(0.75),
          style: StrokeStyle(
            lineWidth: 2.5, lineCap: .round, dash: [6, 8], dashPhase: shift * route.length))

      // Current stop. Its caption fades where it stands instead of trailing the bead.
      stopDot(at: leaving)
        .opacity(visibility(at: -shift))
      startLabel(city: currentCity, at: route.start)
        .opacity(Double(max(0, 1 - shift * 6)))

      // Next stop: its caption turns into the accepted city, then it slides to the start.
      stopDot(at: arriving)
      finishLabel(city: nil, at: arriving)
        .opacity((1 - reveal) * captionOut)
      if let incomingCity {
        finishLabel(city: incomingCity, at: arriving)
          .opacity(reveal * captionOut)
        startLabel(city: incomingCity, at: arriving)
          .opacity(captionIn)

        // The fresh unknown stop entering from past the finish; its caption appears
        // in place together with the bead.
        stopDot(at: route.point(at: 2 - shift))
          .opacity(visibility(at: 2 - shift))
        finishLabel(city: nil, at: route.finish)
          .opacity(visibility(at: 2 - shift))
      }

      // The car stays mid-route and only rocks while the route is moving.
      let carPoint = route.point(at: 0.5)
      JourneyCar(isDriving: isDriving)
        .position(x: carPoint.x, y: carPoint.y - 16)
        .opacity(isDriving ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isDriving)
    }
  }

  private func visibility(at position: CGFloat) -> Double {
    Double(max(0, 1 - route.overshoot(at: position) / fadeDistance))
  }

  private func stopDot(at point: CGPoint) -> some View {
    ZStack {
      Circle()
        .fill(Color(red: 0.91, green: 0.95, blue: 1))
        .frame(width: 34, height: 34)
      Circle()
        .fill(CityChainPalette.blue.gradient)
        .frame(width: 17, height: 17)
    }
    .position(point)
  }

  /// To the right of the stop.
  private func startLabel(city: USCity?, at point: CGPoint) -> some View {
    let width = route.size.width * 0.42
    return stopLabel(
      title: city?.name ?? String(localized: "Start"),
      subtitle: subtitle(for: city, placeholder: String(localized: "Choose a city")))
      .frame(width: width, alignment: .leading)
      .position(x: point.x + 20 + width / 2, y: point.y)
  }

  /// Under the stop: block right-aligned to the card edge, lines left-aligned.
  private func finishLabel(city: USCity?, at point: CGPoint) -> some View {
    let width = route.size.width * 0.5
    let trailing = point.x + route.size.width * 0.955 - route.finish.x
    return stopLabel(
      title: city?.name ?? String(localized: "Next"),
      subtitle: subtitle(for: city, placeholder: String(localized: "Keep going")))
      .frame(width: width, height: 42, alignment: .topTrailing)
      .position(x: trailing - width / 2, y: point.y + 15 + 21)
  }

  private func stopLabel(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)
      Text(subtitle)
        .font(.footnote)
        .foregroundStyle(CityChainPalette.secondaryInk)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    // Keeps names legible where they cross the scenery.
    .shadow(color: .white, radius: 2)
    .shadow(color: .white, radius: 2)
  }

  private func subtitle(for city: USCity?, placeholder: String) -> String {
    guard let city else { return placeholder }
    return city.state.map { "\($0.name) · \($0.abbreviation)" } ?? String(localized: "United States")
  }
}

private struct RouteJourneyCanvas: View {
  let currentCity: USCity?
  let incomingCity: USCity?
  let progress: CGFloat
  let reveal: Double
  let isDriving: Bool
  @ScaledMetric(relativeTo: .caption) private var laneHeight = 100

  var body: some View {
    ViewThatFits(in: .horizontal) {
      content(isWide: true)
        .frame(minWidth: 560)
      content(isWide: false)
    }
  }

  @ViewBuilder
  private func content(isWide: Bool) -> some View {
    VStack(alignment: .leading, spacing: isWide ? 8 : 12) {
      HStack(alignment: .center) {
        Text("Your route")
          .font(.system(isWide ? .title2 : .headline, design: .rounded, weight: .heavy))
          .foregroundStyle(CityChainPalette.ink)
          .padding(.leading, isWide ? 14 : 8)
        Spacer(minLength: 8)
        RoutePlaceholderCloud()
          .fill(Color(red: 0.85, green: 0.94, blue: 0.98).gradient)
          .frame(width: isWide ? 48 : 38, height: isWide ? 24 : 18)
          .accessibilityHidden(true)
      }

      GeometryReader { geometry in
        if isWide {
          wideRoute(width: geometry.size.width)
        } else {
          compactRoute(width: geometry.size.width)
        }
      }
      .frame(height: isWide ? 48 : laneHeight)
      .clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibleRoute)

      RouteJourneyFooter(isWide: isWide)
    }
    .padding(.horizontal, isWide ? 20 : 10)
    .padding(.vertical, isWide ? 8 : 18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(CityChainPalette.ink.opacity(0.06), lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .shadow(color: CityChainPalette.ink.opacity(0.04), radius: 12, y: 5)
  }

  private func compactRoute(width: CGFloat) -> some View {
    let labelWidth = width * 0.42
    let travelDistance = width - labelWidth
    return ZStack(alignment: .topLeading) {
      JourneyTrail()
        .stroke(
          CityChainPalette.blue.opacity(0.38),
          style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 7]))
        .frame(width: travelDistance, height: 22)
        .offset(x: labelWidth / 2, y: 4)
        .accessibilityHidden(true)

      if let currentCity {
        JourneyEndpoint(city: currentCity)
          .id(currentCity.id)
          .frame(width: labelWidth)
          .offset(x: incomingCity == nil ? 0 : -progress * (labelWidth + 18))
          .transition(.identity)
      } else {
        JourneyEndpoint(city: nil, isFirstStop: true)
          .frame(width: labelWidth)
          .offset(x: -progress * (labelWidth + 18))
      }

      JourneyEndpoint(city: nil)
        .frame(width: labelWidth)
        .opacity(incomingCity == nil ? 1 : 1 - reveal)
        .offset(x: travelDistance)

      if let incomingCity {
        JourneyEndpoint(city: incomingCity)
          .id(incomingCity.id)
          .frame(width: labelWidth)
          .opacity(reveal)
          .offset(x: travelDistance * (1 - progress))
          .transition(.opacity)
      }

      JourneyCar(isDriving: isDriving)
        .frame(width: 40, height: 30)
        .offset(x: (width - 40) / 2)
        .zIndex(1)
        .accessibilityHidden(true)
    }
  }

  private func wideRoute(width: CGFloat) -> some View {
    let endpointWidth = width * 0.36
    let startX = width * 0.12
    let finishX = width * 0.64
    let travelDistance = finishX - startX
    return ZStack(alignment: .topLeading) {
      JourneyTrail()
        .stroke(
          CityChainPalette.blue.opacity(0.45),
          style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 7]))
        .frame(width: width * 0.33, height: 22)
        .offset(x: width * 0.34, y: 12)
        .accessibilityHidden(true)

      if let currentCity {
        JourneyWideEndpoint(city: currentCity)
          .id(currentCity.id)
          .frame(width: endpointWidth, alignment: .leading)
          .offset(x: incomingCity == nil ? startX : startX - progress * (endpointWidth + travelDistance))
          .transition(.identity)
      } else {
        JourneyWideEndpoint(city: nil, isFirstStop: true)
          .frame(width: endpointWidth, alignment: .leading)
          .offset(x: startX - progress * (endpointWidth + travelDistance))
      }

      JourneyWideEndpoint(city: nil)
        .frame(width: endpointWidth, alignment: .leading)
        .opacity(incomingCity == nil ? 1 : 1 - reveal)
        .offset(x: finishX)

      if let incomingCity {
        JourneyWideEndpoint(city: incomingCity, labelOpacity: Double(max(0, 1 - progress * 5)))
          .id(incomingCity.id)
          .frame(width: endpointWidth, alignment: .leading)
          .opacity(reveal)
          .offset(x: finishX - travelDistance * progress)
          .transition(.opacity)
      }

      JourneyCar(isDriving: isDriving)
        .frame(width: 40, height: 30)
        .offset(x: (width - 40) / 2, y: 7)
        .zIndex(1)
        .accessibilityHidden(true)
    }
  }

  private var accessibleRoute: String {
    if let incomingCity, let currentCity {
      return String(localized: "Travelling from \(currentCity.name) to \(incomingCity.name)")
    } else if let incomingCity {
      return String(localized: "First stop: \(incomingCity.name)")
    } else if let currentCity {
      return String(localized: "Current city: \(currentCity.name). Next city is a surprise.")
    }
    return String(localized: "Choose your first city.")
  }
}

private struct RouteJourneyFooter: View {
  let isWide: Bool

  var body: some View {
    ZStack {
      RoutePlaceholderLandscape()
        .frame(width: isWide ? 120 : 112, height: isWide ? 50 : 66)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .offset(x: isWide ? -18 : -12, y: isWide ? 12 : 10)
        .accessibilityHidden(true)
      RoutePlaceholderCompass()
        .frame(width: isWide ? 46 : 40, height: isWide ? 46 : 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .offset(y: isWide ? -16 : -14)
        .accessibilityHidden(true)
      Capsule()
        .fill(Color(red: 0.91, green: 0.95, blue: 1))
        .frame(width: isWide ? 200 : 176, height: 34)
      Text("One city at a time.")
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(CityChainPalette.secondaryInk)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(height: isWide ? 50 : 68)
  }
}

private struct JourneyWideEndpoint: View {
  let city: USCity?
  var isFirstStop = false

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      ZStack {
        Circle()
          .fill(CityChainPalette.blue.gradient)
          .frame(width: city == nil ? 34 : 18, height: city == nil ? 34 : 18)
        if city == nil {
          Text("?")
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
        }
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(city?.name ?? String(localized: isFirstStop ? "Start" : "Next"))
          .font(.system(.subheadline, design: .rounded, weight: .bold))
          .foregroundStyle(CityChainPalette.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(CityChainPalette.secondaryInk)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .opacity(labelOpacity)
    }
  }

  var labelOpacity = 1.0

  private var subtitle: String {
    if let city {
      return city.state.map { "\($0.name) · \($0.abbreviation)" }
        ?? String(localized: "United States")
    }
    return String(localized: isFirstStop ? "Choose a city" : "Keep the chain going")
  }
}

private struct JourneyEndpoint: View {
  let city: USCity?
  var isFirstStop = false

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle()
          .fill(CityChainPalette.blue.gradient)
          .frame(width: city == nil ? 28 : 14, height: city == nil ? 28 : 14)
        if city == nil {
          Text("?")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        }
      }
      .frame(height: 30)
      .accessibilityHidden(true)

      Text(city?.name ?? String(localized: isFirstStop ? "Start" : "Next city"))
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)
        .multilineTextAlignment(.center)
        .lineLimit(2)

      Text(subtitle)
        .font(.caption)
        .foregroundStyle(CityChainPalette.secondaryInk)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }

  private var subtitle: String {
    if let city {
      return city.state.map { "\($0.name) · \($0.abbreviation)" }
        ?? String(localized: "United States")
    }
    return String(localized: isFirstStop ? "Choose a city" : "Keep going")
  }
}

/// Motion is scoped to the car, so it cannot animate the card's keyboard/layout changes.
private struct JourneyCar: View {
  let isDriving: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    if isDriving && !reduceMotion && scenePhase == .active {
      sprite.phaseAnimator([false, true]) { car, phase in
        car
          .rotationEffect(.degrees(phase ? 2 : -2))
          .offset(y: phase ? -1.5 : 1)
      } animation: { _ in
        .easeInOut(duration: 0.22)
      }
    } else {
      sprite
    }
  }

  private var sprite: some View {
    Image(systemName: "car.side.fill")
      .font(.title3)
      .foregroundStyle(CityChainPalette.teal)
      .scaleEffect(x: -1, y: 1)
      .padding(.horizontal, 4)
      .background(.white, in: Capsule())
  }
}

private struct JourneyTrail: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.midY),
        control1: CGPoint(x: rect.width * 0.35, y: rect.minY),
        control2: CGPoint(x: rect.width * 0.65, y: rect.maxY))
    }
  }
}

#Preview("Your route — next city unknown", traits: .sizeThatFitsLayout) {
  RouteJourneyCanvas(
    currentCity: USCity("Austin", state: .texas),
    incomingCity: nil, progress: 0, reveal: 0, isDriving: false)
    .frame(width: 350)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — travelling", traits: .sizeThatFitsLayout) {
  RouteJourneyCanvas(
    currentCity: USCity("Austin", state: .texas),
    incomingCity: USCity("Newark", state: .newJersey),
    progress: 0.5, reveal: 1, isDriving: true)
    .frame(width: 350)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — wide", traits: .sizeThatFitsLayout) {
  RouteJourneyCanvas(
    currentCity: USCity("New Orleans", state: .louisiana),
    incomingCity: nil, progress: 0, reveal: 0, isDriving: false)
    .frame(width: 660)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — wide travelling", traits: .sizeThatFitsLayout) {
  RouteJourneyCanvas(
    currentCity: USCity("New Orleans", state: .louisiana),
    incomingCity: USCity("Austin", state: .texas),
    progress: 0.5, reveal: 1, isDriving: true)
    .frame(width: 660)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — illustrated empty", traits: .sizeThatFitsLayout) {
  ScenicRouteJourneyCanvas(
    currentCity: nil, incomingCity: nil, progress: 0, reveal: 0, isDriving: false)
    .frame(width: 350)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — illustrated", traits: .sizeThatFitsLayout) {
  ScenicRouteJourneyCanvas(
    currentCity: USCity("Oklahoma City", state: .oklahoma),
    incomingCity: nil, progress: 0, reveal: 0, isDriving: false)
    .frame(width: 350)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — illustrated travelling", traits: .sizeThatFitsLayout) {
  ScenicRouteJourneyCanvas(
    currentCity: USCity("Austin", state: .texas),
    incomingCity: USCity("Newark", state: .newJersey),
    progress: 0.45, reveal: 1, isDriving: true)
    .frame(width: 350)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — illustrated filmstrip", traits: .sizeThatFitsLayout) {
  // Frames of one leg: reveal, then the thread pulls every stop one place back.
  VStack(spacing: 12) {
    ForEach([(0.0, 1.0), (0.1, 1.0), (0.5, 1.0), (0.9, 1.0)], id: \.0) { progress, reveal in
      ScenicRouteJourneyCanvas(
        currentCity: USCity("Austin", state: .texas),
        incomingCity: USCity("Newark", state: .newJersey),
        progress: progress, reveal: reveal, isDriving: true)
    }
  }
  .frame(width: 350)
  .padding(20)
  .background(CityChainPalette.paper)
}

#Preview("Your route — illustrated wide", traits: .sizeThatFitsLayout) {
  ScenicRouteJourneyCanvas(
    currentCity: USCity("New Orleans", state: .louisiana),
    incomingCity: nil, progress: 0, reveal: 0, isDriving: false)
    .frame(width: 620)
    .padding(20)
    .background(CityChainPalette.paper)
}

#Preview("Your route — play two replies", traits: .sizeThatFitsLayout) {
  RouteJourneyPlaybackPreview()
}

private struct RouteJourneyPlaybackPreview: View {
  @State private var cities = [
    USCity("Austin", state: .texas), USCity("Newark", state: .newJersey),
  ]

  var body: some View {
    VStack(spacing: 16) {
      ScenicRouteJourneyCard(cities: cities, isWaitingForScout: false)
      HStack {
        Button("Play two replies") {
          // Both replies in one update exercise the animation queue.
          cities += [USCity("Kansas City", state: .missouri), USCity("Yonkers", state: .newYork)]
        }
        .disabled(cities.count > 2)
        Button("Reset") {
          cities = [USCity("Austin", state: .texas), USCity("Newark", state: .newJersey)]
        }
      }
    }
    .frame(width: 350)
    .padding(20)
    .background(CityChainPalette.paper)
  }
}
