import CityChainGame
import CityChainPresentation
import SwiftUI

struct CityAtlasMapView: View {
  static let transitionSourceID = "city-atlas-map"

  let visitedCities: [USCity]
  let presentation: ScoutPresentation
  @Binding var selectedCity: USCity?
  let transitionNamespace: Namespace.ID
  let onOpenMapDetail: () -> Void
  var onHapticInteraction: (CityGameHapticInteraction) -> Void = { _ in }
  var onTapScout: (() -> Void)? = nil
  let feedbackMessage: String?
  let feedbackFact: ScoutFact?
  let feedbackIsFinished: Bool
  let onDismissFeedback: () -> Void
  var isNotebook = false
  var notebookScoutGuide: RouteScoutGuide? = nil
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var mapData: CityAtlasMapData? { CityAtlasMapRepository.data }
  private var availableMarkers: [(city: USCity, point: CityAtlasPoint)] {
    guard let mapData else { return [] }
    return visitedCities.compactMap { city in mapData.point(for: city).map { (city, $0) } }
  }
  private var routeSegments: [(from: CityAtlasPoint, to: CityAtlasPoint, region: CityAtlasMapData.Region)] {
    guard let mapData else { return [] }
    return zip(visitedCities, visitedCities.dropFirst()).compactMap { first, second in
      guard
        let from = mapData.point(for: first),
        let to = mapData.point(for: second)
      else { return nil }
      let fromProjection = mapData.projectedPoint(for: from)
      let toProjection = mapData.projectedPoint(for: to)
      guard fromProjection.region == toProjection.region else { return nil }
      return (from, to, fromProjection.region)
    }
  }

  var body: some View {
    if isNotebook {
      notebookMap
    } else {
      pocketAtlas
    }
  }

  /// Notebook upper half: the map alone, as large as the region allows. The map shows
  /// the route; the page layers Scout and his speech over its trailing corner.
  @ViewBuilder
  private var notebookMap: some View {
    if let mapData {
      VStack(spacing: 8) {
        mapCanvas(data: mapData)
          .overlay {
            if let notebookScoutGuide {
              notebookScoutGuide
                .accessibilityIdentifier("cityChain.notebook.scout")
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        CityAtlasSelectionSummary(
          city: selectedCity, latestCity: visitedCities.last,
          hasMapPosition: selectedCity.map { mapData.point(for: $0) != nil } ?? true)
          .padding(.horizontal, 10)
      }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The navigation bar is transparent here, so the map runs up beneath it.
        .ignoresSafeArea(.container, edges: .top)
    } else {
      unavailableMap
    }
  }

  private var unavailableMap: some View {
    ContentUnavailableView(
      "Atlas map unavailable",
      systemImage: "map",
      description: Text("Use the searchable city list while the offline map is unavailable."))
  }

  private var pocketAtlas: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center, spacing: 10) {
            ScoutMapTapTarget(
              presentation: presentation, onTapScout: onTapScout,
              accessibilityIdentifier: "cityChain.scout.mapPanel.openMap"
            ) {
              ScoutView(presentation: presentation)
                .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
              Text("Pocket Atlas")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CityChainPalette.ink)
              Text("Scout keeps track of our discoveries.")
                .font(.caption)
                .foregroundStyle(CityChainPalette.secondaryInk)
            }
            Spacer(minLength: 8)
            Text("50 states")
              .font(.caption.weight(.semibold))
              .foregroundStyle(CityChainPalette.secondaryInk)
          }

          if let mapData {
            mapCanvas(data: mapData)
            CityAtlasSelectionSummary(
              city: selectedCity, latestCity: visitedCities.last,
              hasMapPosition: selectedCity.map { mapData.point(for: $0) != nil } ?? true)

            if let feedbackMessage {
              CityTurnFeedbackView(
                message: feedbackMessage,
                presentation: presentation,
                isFinished: feedbackIsFinished,
                fact: feedbackFact,
                onDismiss: onDismissFeedback)
            }

            if visitedCities.count > 1 {
              if CityAtlasVerticalListSpec().isSatisfiedBy(.init(
                width: geometry.size.width,
                usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize)) {
                CityAtlasVisitedCityList(cities: Array(visitedCities.reversed()), onSelect: {
                  selectedCity = $0
                  onHapticInteraction(.mapCitySelected)
                })
                  .accessibilityIdentifier("cityAtlas.map.visitedCities")
              } else {
                ScrollView(.horizontal) {
                  HStack(spacing: 8) {
                    ForEach(visitedCities) { city in
                      Button {
                        selectedCity = city
                        onHapticInteraction(.mapCitySelected)
                      } label: {
                        Text(city.name)
                          .font(.caption.weight(.semibold))
                          .padding(.horizontal, 11)
                          .padding(.vertical, 8)
                          .background(
                            selectedCity?.id == city.id ? CityChainPalette.sky : .white,
                            in: Capsule())
                      }
                      .buttonStyle(.plain)
                      .accessibilityHint("Shows this visited city on the map")
                    }
                  }
                }
                .scrollIndicators(.hidden)
              }
            }
          } else {
            unavailableMap
          }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.hidden)
      .contentMargins(.top, 18, for: .scrollContent)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder
  private func mapCanvas(data: CityAtlasMapData) -> some View {
    let canvas = CityAtlasMapCanvas(
      data: data, markers: availableMarkers, routeSegments: routeSegments,
      selectedCity: selectedCity,
      visitedStates: Set(visitedCities.compactMap(\.stateAbbreviation)),
      latestState: visitedCities.last?.stateAbbreviation,
      onSelect: { city in
        selectedCity = city
        onHapticInteraction(.mapCitySelected)
      },
      // The notebook map opens in full from Scout and the toolbar instead.
      onOpenMapDetail: isNotebook ? nil : onOpenMapDetail,
      onTapMap: { onHapticInteraction(.mapTapped) },
      showsChrome: !isNotebook,
      insets: isNotebook ? .leading : .below)
      // The card keeps its proportions; the notebook map fills whatever region it gets.
      .aspectRatio(1.16, contentMode: .fit, isEnabled: !isNotebook)
      .accessibilityLabel("Map of the United States. Visited states are highlighted in gold. Alaska and Hawaii are shown in separate insets.")
    if #available(iOS 18.0, *) {
      canvas.matchedTransitionSource(id: Self.transitionSourceID, in: transitionNamespace)
    } else {
      canvas
    }
  }
}

private struct CityAtlasSelectionSummary: View {
  let city: USCity?
  let latestCity: USCity?
  let hasMapPosition: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let city {
        SelectedAtlasCityCard(city: city, isLatest: city.id == latestCity?.id)
        if !hasMapPosition {
          Label("Map position is not available for this city yet.", systemImage: "mappin.slash")
            .font(.caption)
            .foregroundStyle(CityChainPalette.secondaryInk)
            .accessibilityHint("The atlas leaves unknown city locations unmarked.")
        }
      } else {
        Text("Start your trip to mark a city on the map.")
          .font(.subheadline)
          .foregroundStyle(CityChainPalette.secondaryInk)
      }
    }
  }
}

private struct CityAtlasVisitedCityList: View {
  let cities: [USCity]
  let onSelect: (USCity) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Our road trip")
          .font(.system(.title3, design: .rounded, weight: .bold))
          .foregroundStyle(CityChainPalette.ink)
        Spacer()
        Text(cities.count == 1 ? "1 stop" : "\(cities.count) stops")
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(CityChainPalette.blue)
      }
      .padding(.bottom, 12)

      LazyVStack(spacing: 8) {
        ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
          Button { onSelect(city) } label: {
            HStack(spacing: 12) {
              Text("\(cities.count - index)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(CityChainPalette.blue)
                .frame(width: 34, height: 34)
                .background(CityChainPalette.sky.opacity(0.72), in: Circle())
              VStack(alignment: .leading, spacing: 3) {
                Text(city.name)
                  .font(.system(.body, design: .rounded, weight: .bold))
                  .foregroundStyle(CityChainPalette.ink)
                Text(city.state.map { "\($0.name) · \($0.abbreviation)" } ?? "United States")
                  .font(.caption)
                  .foregroundStyle(CityChainPalette.secondaryInk)
              }
              Spacer(minLength: 0)
              Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CityChainPalette.teal)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
          }
          .buttonStyle(.plain)
          .accessibilityHint("Shows this visited city on the map")
        }
      }
    }
  }
}

private struct CityAtlasMapCanvas: View {
  let data: CityAtlasMapData
  let markers: [(city: USCity, point: CityAtlasPoint)]
  let routeSegments: [(from: CityAtlasPoint, to: CityAtlasPoint, region: CityAtlasMapData.Region)]
  let selectedCity: USCity?
  let visitedStates: Set<String>
  let latestState: String?
  let onSelect: (USCity) -> Void
  var onOpenMapDetail: (() -> Void)? = nil
  var onTapMap: () -> Void = {}
  /// Card treatment: background, title, legend and compass. The notebook map drops it
  /// and blends into the page instead.
  var showsChrome = true
  var insets = AtlasMapFrames.InsetPlacement.below

  var body: some View {
    GeometryReader { geometry in
      let layout = AtlasMapFrames(size: geometry.size, insets: insets)
      ZStack(alignment: .topLeading) {
        LinearGradient(
          colors: [
            Color(red: 1, green: 0.98, blue: 0.93),
            Color(red: 0.95, green: 0.97, blue: 0.92),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
          .opacity(showsChrome ? 1 : 0)
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .contentShape(RoundedRectangle(cornerRadius: 18))
          .onTapGesture(perform: onTapMap)

        Canvas { context, _ in
          for region in [CityAtlasMapData.Region.mainland, .alaska, .hawaii] {
            var landmass = Path()
            for state in data.states where state.region == region {
              landmass.addPath(state.simplePath, transform: layout.transform(for: region))
            }
            var shadowContext = context
            shadowContext.clip(to: Path(layout.frame(for: region)))
            shadowContext.addFilter(.shadow(
              color: Color(red: 0.35, green: 0.49, blue: 0.43).opacity(0.17),
              radius: 4, x: 0, y: 2))
            shadowContext.fill(landmass, with: .color(.black.opacity(0.28)), style: FillStyle(eoFill: true))
          }
          for (index, state) in data.states.enumerated() {
            var path = Path()
            path.addPath(state.simplePath, transform: layout.transform(for: state.region))
            let colors: [Color] = visitedStates.contains(state.abbreviation)
              ? [Color(red: 1, green: 0.87, blue: 0.49), Color(red: 0.98, green: 0.73, blue: 0.29)]
              : [Color(red: 0.79, green: 0.89, blue: 0.72),
                 Color(red: 0.62 + Double(index % 3) * 0.035, green: 0.80, blue: 0.66)]
            let frame = layout.fittedFrame(for: state.region)
            var regionContext = context
            regionContext.clip(to: Path(layout.frame(for: state.region)))
            regionContext.fill(path, with: .linearGradient(
              Gradient(colors: colors), startPoint: frame.origin,
              endPoint: CGPoint(x: frame.maxX, y: frame.maxY)), style: FillStyle(eoFill: true))
          }
          // Draw borders after every fill so neighboring shapes cannot cover them.
          for state in data.states {
            var path = Path()
            path.addPath(state.simplePath, transform: layout.transform(for: state.region))
            var regionContext = context
            regionContext.clip(to: Path(layout.frame(for: state.region)))
            regionContext.stroke(path, with: .color(Color(red: 1, green: 0.98, blue: 0.90)), lineWidth: 1.1)
            if state.abbreviation == latestState {
              regionContext.stroke(path, with: .color(Color(red: 0.85, green: 0.54, blue: 0.17)), lineWidth: 1.5)
            }
          }
          drawAtlasLandmarks(in: &context, layout: layout)
          for (index, segment) in routeSegments.enumerated() {
            let from = data.projectedPoint(for: segment.from)
            let to = data.projectedPoint(for: segment.to)
            guard from.region == segment.region, to.region == segment.region else { continue }
            var path = Path()
            let start = layout.project(from.point, for: segment.region)
            let end = layout.project(to.point, for: segment.region)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let distance = max(1, hypot(dx, dy))
            let bend = min(24, max(9, distance * 0.16)) * (index.isMultiple(of: 2) ? 1 : -1)
            let control = CGPoint(x: (start.x + end.x) / 2 - dy / distance * bend,
                                  y: (start.y + end.y) / 2 + dx / distance * bend)
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            context.stroke(path, with: .color(.white.opacity(0.92)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))
            context.stroke(
              path,
              with: .color(Color(red: 0.22, green: 0.48, blue: 0.73)),
              style: StrokeStyle(lineWidth: 3.1, lineCap: .round, dash: [7, 5]))
          }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)

        if let onOpenMapDetail {
          Button {
            onTapMap()
            onOpenMapDetail()
          } label: {
            ZStack(alignment: .topTrailing) {
              Color.clear
              Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CityChainPalette.ink)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.94), in: Circle())
                .overlay(Circle().strokeBorder(CityChainPalette.ink.opacity(0.12)))
                .padding(10)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open map detail")
          .accessibilityHint("Opens a larger interactive map")
        }

        if showsChrome {
          Text("UNITED STATES")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(CityChainPalette.secondaryInk)
            .position(x: layout.mainland.midX, y: 13)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }

        ForEach(markers, id: \.point.id) { marker in
          let projected = data.projectedPoint(for: marker.point)
          let position = layout.project(projected.point, for: projected.region)
          Button {
            onSelect(marker.city)
          } label: {
            Group {
              if selectedCity?.id == marker.city.id {
                Image(systemName: "mappin.circle.fill")
                  .font(.system(size: 26, weight: .bold))
                  .symbolRenderingMode(.palette)
                  .foregroundStyle(.white, Color(red: 0.91, green: 0.60, blue: 0.18))
              } else {
                Circle()
                  .fill(CityChainPalette.blue)
                  .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                  .frame(width: 13, height: 13)
              }
            }
              .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .position(position)
          .accessibilityLabel("\(marker.city.name), \(marker.city.stateName ?? "United States")")
          .accessibilityHint("Shows this visited city on the map")
        }

        if let marker = markers.first(where: { $0.city.id == selectedCity?.id }) {
          let projected = data.projectedPoint(for: marker.point)
          let anchor = layout.project(projected.point, for: projected.region)
          let regionFrame = layout.fittedFrame(for: projected.region)
          let labelWidth = min(144, max(94, regionFrame.width * 0.43))
          let goesLeft = anchor.x > regionFrame.midX
          let labelX = min(regionFrame.maxX - labelWidth / 2 - 3,
                           max(regionFrame.minX + labelWidth / 2 + 3,
                               anchor.x + (goesLeft ? -labelWidth / 2 - 15 : labelWidth / 2 + 15)))
          let labelY = min(regionFrame.maxY - 15, max(regionFrame.minY + 14, anchor.y - 25))
          Text(marker.city.name)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(Color(red: 0.25, green: 0.31, blue: 0.31))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: labelWidth)
            .background(Color(red: 1, green: 0.98, blue: 0.91), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(red: 0.89, green: 0.69, blue: 0.34), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            .position(x: labelX, y: labelY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        AtlasInsetLabel(title: "Alaska", abbreviation: "AK")
          .position(x: layout.alaska.midX, y: layout.alaska.minY - 7)
          .allowsHitTesting(false)
        AtlasInsetLabel(title: "Hawaii", abbreviation: "HI")
          .position(x: layout.hawaii.midX, y: layout.hawaii.minY - 7)
          .allowsHitTesting(false)

        if showsChrome {
          VStack(spacing: 3) {
            Text("So much to explore!")
              .font(.system(.caption2, design: .rounded, weight: .bold))
              .foregroundStyle(CityChainPalette.teal)
            HStack(spacing: 4) {
              Circle().fill(Color(red: 0.98, green: 0.76, blue: 0.34))
                .frame(width: 7, height: 7)
              Text("Visited states")
                .font(.caption2)
                .foregroundStyle(CityChainPalette.secondaryInk)
            }
          }
          .position(x: geometry.size.width * 0.73, y: geometry.size.height - 69)
          .allowsHitTesting(false)

          AtlasCompassView()
            .frame(width: 43, height: 43)
            .position(x: geometry.size.width * 0.82, y: geometry.size.height - 29)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .background(.clear, in: RoundedRectangle(cornerRadius: 18))
      .clipShape(RoundedRectangle(cornerRadius: showsChrome ? 18 : 0))
    }
  }

  private func drawAtlasLandmarks(in context: inout GraphicsContext, layout: AtlasMapFrames) {
    let frame = layout.fittedFrame(for: .mainland)
    let waterPuffs: [(CGFloat, CGFloat, CGFloat)] = [
      (0.01, 0.69, 14), (0.99, 0.63, 17), (0.53, 0.99, 17),
    ]
    for (x, y, radius) in waterPuffs {
      let center = CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
      var puff = Path()
      puff.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.38,
                                 width: radius * 1.25, height: radius * 0.8))
      puff.addEllipse(in: CGRect(x: center.x - radius * 0.35, y: center.y - radius * 0.72,
                                 width: radius * 1.2, height: radius * 1.1))
      puff.addEllipse(in: CGRect(x: center.x + radius * 0.35, y: center.y - radius * 0.32,
                                 width: radius, height: radius * 0.7))
      context.fill(puff, with: .color(Color(red: 0.81, green: 0.92, blue: 0.94).opacity(0.48)))
    }
    let waves: [(CGFloat, CGFloat)] = [(0.01, 0.80), (0.99, 0.74), (0.60, 0.99)]
    for (x, y) in waves {
      let center = CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
      var wave = Path()
      wave.move(to: CGPoint(x: center.x - 7, y: center.y))
      wave.addQuadCurve(to: CGPoint(x: center.x, y: center.y), control: CGPoint(x: center.x - 3.5, y: center.y - 4))
      wave.addQuadCurve(to: CGPoint(x: center.x + 7, y: center.y), control: CGPoint(x: center.x + 3.5, y: center.y + 4))
      context.stroke(wave, with: .color(Color(red: 0.38, green: 0.70, blue: 0.82).opacity(0.72)),
                     style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
    let mountainSize = min(22, max(12, frame.width * 0.035))
    let mountains: [(CGFloat, CGFloat, CGFloat)] = [(0.24, 0.50, 1), (0.30, 0.53, 0.72)]
    for (x, y, scale) in mountains {
      let center = CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
      let width = mountainSize * scale
      let height = mountainSize * scale * 0.78
      let peakPoint = CGPoint(x: center.x, y: center.y - height)
      var mountain = Path()
      mountain.move(to: CGPoint(x: center.x - width, y: center.y))
      mountain.addLine(to: peakPoint)
      mountain.addLine(to: CGPoint(x: center.x + width, y: center.y))
      mountain.closeSubpath()
      context.fill(mountain, with: .color(Color(red: 0.55, green: 0.67, blue: 0.57).opacity(0.52)))

      var snow = Path()
      snow.move(to: peakPoint)
      snow.addLine(to: CGPoint(x: center.x - width * 0.28, y: center.y - height * 0.43))
      snow.addLine(to: CGPoint(x: center.x, y: center.y - height * 0.59))
      snow.addLine(to: CGPoint(x: center.x + width * 0.31, y: center.y - height * 0.39))
      snow.closeSubpath()
      context.fill(snow, with: .color(Color(red: 0.98, green: 0.97, blue: 0.91).opacity(0.88)))
    }

    let trees: [(CGFloat, CGFloat)] = [(0.19, 0.30), (0.23, 0.32), (0.32, 0.39), (0.78, 0.35), (0.82, 0.38)]
    let treeSize = min(18, max(11, frame.width * 0.035))
    for (x, y) in trees {
      let center = CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
      let canopyLayers: [(CGFloat, CGFloat, CGFloat)] = [
        (1.0, 0.46, 0.27), (0.72, 0.16, 0.48), (0.42, -0.12, 0.70),
      ]
      for (topOffset, baseOffset, halfWidth) in canopyLayers {
        var canopy = Path()
        canopy.move(to: CGPoint(x: center.x, y: center.y - treeSize * topOffset))
        canopy.addLine(to: CGPoint(x: center.x - treeSize * halfWidth, y: center.y - treeSize * baseOffset))
        canopy.addLine(to: CGPoint(x: center.x + treeSize * halfWidth, y: center.y - treeSize * baseOffset))
        canopy.closeSubpath()
        context.fill(canopy, with: .color(Color(red: 0.34, green: 0.55, blue: 0.43).opacity(0.68)))
      }
      let trunkWidth = max(1.5, treeSize * 0.12)
      context.fill(
        Path(CGRect(x: center.x - trunkWidth / 2, y: center.y - treeSize * 0.12,
                    width: trunkWidth, height: treeSize * 0.48)),
        with: .color(Color(red: 0.48, green: 0.37, blue: 0.27).opacity(0.62)))
    }
  }
}

private struct AtlasCompassView: View {
  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = size.width * 0.27
      let ink = Color(red: 0.38, green: 0.57, blue: 0.63)
      context.stroke(
        Path(ellipseIn: CGRect(
          x: center.x - radius, y: center.y - radius,
          width: radius * 2, height: radius * 2)),
        with: .color(ink.opacity(0.55)), lineWidth: 1)
      for index in 0..<4 {
        let angle = Double(index) * .pi / 2 - .pi / 2
        let tip = CGPoint(
          x: center.x + cos(angle) * radius * 1.2,
          y: center.y + sin(angle) * radius * 1.2)
        let side = CGPoint(x: -sin(angle) * radius * 0.22, y: cos(angle) * radius * 0.22)
        var point = Path()
        point.move(to: tip)
        point.addLine(to: CGPoint(x: center.x + side.x, y: center.y + side.y))
        point.addLine(to: center)
        point.addLine(to: CGPoint(x: center.x - side.x, y: center.y - side.y))
        point.closeSubpath()
        context.fill(point, with: .color(ink.opacity(index.isMultiple(of: 2) ? 0.85 : 0.45)))
      }
      let directions: [(String, CGFloat, CGFloat)] = [
        ("N", 0.5, 0.06), ("E", 0.94, 0.5), ("S", 0.5, 0.94), ("W", 0.06, 0.5),
      ]
      for (title, x, y) in directions {
        context.draw(
          Text(verbatim: title)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(ink),
          at: CGPoint(x: size.width * x, y: size.height * y))
      }
    }
  }
}

private struct AtlasInsetLabel: View {
  let title: String
  let abbreviation: String

  var body: some View {
    HStack(spacing: 3) {
      Text(title)
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)
      Text(abbreviation)
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .foregroundStyle(CityChainPalette.secondaryInk)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct SelectedAtlasCityCard: View {
  let city: USCity
  let isLatest: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(isLatest ? "LATEST STOP" : "SELECTED STOP")
        .font(.caption2.weight(.bold))
        .tracking(0.8)
        .foregroundStyle(CityChainPalette.teal)
      Text(city.name)
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundStyle(CityChainPalette.ink)
      HStack(spacing: 8) {
        Text(city.state?.name ?? "United States")
        if let abbreviation = city.stateAbbreviation {
          Text(abbreviation)
            .fontWeight(.bold)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(CityChainPalette.sky, in: Capsule())
        }
        if city.isStateCapital {
          Label("State capital", systemImage: "star.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CityChainPalette.teal)
        }
      }
      .font(.subheadline)
      .foregroundStyle(CityChainPalette.secondaryInk)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(CityChainPalette.paper, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}

struct CityAtlasMapDetailView<RouteContent: View>: View {
  let visitedCities: [USCity]
  let presentation: ScoutPresentation
  @Binding var selectedCity: USCity?
  let fact: ScoutFact?
  let onSelectCity: (USCity) -> Void
  let onDismissFact: () -> Void
  var onDismissMap: () -> Void = {}
  var onHapticInteraction: (CityGameHapticInteraction) -> Void = { _ in }
  @ViewBuilder let routeContent: () -> RouteContent
  @Environment(\.dismiss) private var dismiss
  @State private var scoutOverlayHeight: CGFloat = 200

  private var mapData: CityAtlasMapData? { CityAtlasMapRepository.data }
  private var markers: [(city: USCity, point: CityAtlasPoint)] {
    guard let mapData else { return [] }
    return visitedCities.compactMap { city in mapData.point(for: city).map { (city, $0) } }
  }
  private var routeSegments: [(from: CityAtlasPoint, to: CityAtlasPoint, region: CityAtlasMapData.Region)] {
    guard let mapData else { return [] }
    return zip(visitedCities, visitedCities.dropFirst()).compactMap { first, second in
      guard let from = mapData.point(for: first), let to = mapData.point(for: second) else { return nil }
      let fromProjection = mapData.projectedPoint(for: from)
      let toProjection = mapData.projectedPoint(for: to)
      guard fromProjection.region == toProjection.region else { return nil }
      return (from, to, fromProjection.region)
    }
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Pocket Atlas")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CityChainPalette.ink)
              Text("Tap a city to hear a fact from Scout.")
                .font(.subheadline)
                .foregroundStyle(CityChainPalette.secondaryInk)
            }
            Spacer(minLength: 8)
            Button {
              dismiss()
            } label: {
              Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(CityChainPalette.paper, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cityAtlas.map.close")
          }

          if let mapData {
            CityAtlasMapCanvas(
              data: mapData, markers: markers, routeSegments: routeSegments,
              selectedCity: selectedCity,
              visitedStates: Set(visitedCities.compactMap(\.stateAbbreviation)),
              latestState: visitedCities.last?.stateAbbreviation,
              onSelect: onSelectCity,
              onTapMap: { onHapticInteraction(.mapTapped) })
              .aspectRatio(1.16, contentMode: .fit)
              .accessibilityLabel("Interactive map of the United States. Visited states are highlighted in gold. Alaska and Hawaii are shown in separate insets.")

            if let selectedCity {
              Button { onSelectCity(selectedCity) } label: {
                SelectedAtlasCityCard(
                  city: selectedCity, isLatest: selectedCity.id == visitedCities.last?.id)
              }
              .buttonStyle(.plain)
              .accessibilityHint("Shows a fact about this city or its state")
              .accessibilityIdentifier("cityAtlas.map.selectedCity")
              if mapData.point(for: selectedCity) == nil {
                Label("Map position is not available for this city yet.", systemImage: "mappin.slash")
                  .font(.caption)
                  .foregroundStyle(CityChainPalette.secondaryInk)
              }
            } else {
              Text("Choose one of your visited markers to inspect a city.")
                .font(.subheadline)
                .foregroundStyle(CityChainPalette.secondaryInk)
            }
            routeContent()
          } else {
            ContentUnavailableView(
              "Atlas map unavailable",
              systemImage: "map",
              description: Text("The offline map is unavailable."))
          }
        }
        .padding(20)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(minHeight: geometry.size.height, alignment: .top)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(CityChainPalette.ink.opacity(0.08)))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .scrollIndicators(.hidden)
      // Keep the last stop reachable while the map scrolls behind Scout.
      .contentMargins(.bottom, scoutOverlayHeight + 12, for: .scrollContent)
      .overlay(alignment: .bottomTrailing) {
        ScoutSpeechFeedbackView(
          message: fact?.text,
          presentation: presentation,
          isCompact: false,
          onDismiss: onDismissFact,
          fact: fact,
          companionSize: 176,
          horizontalPadding: 20,
          bubbleAlignment: .top)
          .padding(.vertical, 8)
          .frame(maxWidth: 620)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            scoutOverlayHeight = height
          }
          .accessibilityIdentifier("cityAtlas.map.scout")
      }
      .background(CityChainPalette.paper)
    }
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .onDisappear(perform: onDismissMap)
  }
}

private struct AtlasMapFrames {
  enum InsetPlacement {
    /// Alaska and Hawaii in a row under the mainland (the square card map).
    case below
    /// Alaska over Hawaii in a narrow leading column under the west coast, keeping
    /// the trailing side clear for Scout (the notebook map).
    case leading
  }

  let mainland: CGRect
  let alaska: CGRect
  let hawaii: CGRect

  init(size: CGSize, insets: InsetPlacement = .below) {
    switch insets {
    case .below:
      let insetHeight = size.width * 0.22
      mainland = CGRect(
        x: 12, y: 27, width: size.width - 24,
        height: size.height - insetHeight - 42)
      alaska = CGRect(
        x: 14, y: size.height - insetHeight - 8,
        width: size.width * 0.28, height: insetHeight)
      hawaii = CGRect(
        x: alaska.maxX + 8, y: alaska.minY + insetHeight * 0.28,
        width: size.width * 0.18, height: insetHeight * 0.62)
    case .leading:
      // Hug the top-leading corner: the mainland rises under the transparent bar and
      // its east coast ends before the trailing third, where Scout stands.
      let width = size.width * 0.7 - 8
      let top = min(40, size.height * 0.08)
      mainland = CGRect(
        x: 8, y: top, width: width,
        height: min(size.height - top - 8, width / Self.aspect(for: .mainland)))
      // Alaska over Hawaii in the Pacific, under the west coast.
      let column = min(size.width * 0.18, size.height * 0.36)
      alaska = CGRect(
        x: 10, y: max(mainland.midY + 10, size.height * 0.56),
        width: column, height: size.height * 0.2)
      hawaii = CGRect(
        x: 14, y: alaska.maxY + 22, width: column * 0.8, height: size.height * 0.12)
    }
  }

  func frame(for region: CityAtlasMapData.Region) -> CGRect {
    switch region {
    case .mainland: mainland
    case .alaska: alaska
    case .hawaii: hawaii
    }
  }

  func project(_ point: CGPoint, in frame: CGRect) -> CGPoint {
    CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
  }

  func project(_ point: CGPoint, for region: CityAtlasMapData.Region) -> CGPoint {
    project(point, in: fittedFrame(for: region))
  }

  func transform(for region: CityAtlasMapData.Region) -> CGAffineTransform {
    let frame = fittedFrame(for: region)
    return CGAffineTransform(
      a: frame.width / 1000, b: 0, c: 0, d: frame.height / 1000,
      tx: frame.minX, ty: frame.minY)
  }

  static func aspect(for region: CityAtlasMapData.Region) -> CGFloat {
    let bounds = CityAtlasMapData.bounds(for: region)
    let centerLatitude = (bounds.north + bounds.south) / 2 * .pi / 180
    return CGFloat((bounds.east - bounds.west) * cos(centerLatitude)
      / (bounds.north - bounds.south))
  }

  func fittedFrame(for region: CityAtlasMapData.Region) -> CGRect {
    let container = frame(for: region)
    let aspect = Self.aspect(for: region)
    let width = container.width / container.height > aspect ? container.height * aspect : container.width
    let height = width / aspect
    return CGRect(
      x: container.midX - width / 2, y: container.midY - height / 2,
      width: width, height: height)
  }
}

private struct CityAtlasRoutePreview: View {
  var showsDetail = false
  @State private var selectedCity: USCity? = USCity("Nashville", state: .tennessee, isStateCapital: true)
  @State private var fact = ScoutFactCatalog.bundled()?.facts.first { $0.stateCode == "TN" }
  @Namespace private var transitionNamespace

  private let visitedCities = [
    USCity("Austin", state: .texas, isStateCapital: true),
    USCity("Nashville", state: .tennessee, isStateCapital: true),
  ]

  var body: some View {
    Group {
      if showsDetail {
        CityAtlasMapDetailView(
          visitedCities: visitedCities,
          presentation: ScoutPresentation(pose: fact == nil ? .welcome : .tryAnother),
          selectedCity: $selectedCity,
          fact: fact,
          onSelectCity: { city in
            selectedCity = city
            fact = ScoutFactCatalog.bundled()?.facts.first { $0.stateCode == city.stateAbbreviation }
          },
          onDismissFact: { fact = nil }) {
            EmptyView()
          }
      } else {
        CityAtlasMapView(
          visitedCities: visitedCities,
          presentation: ScoutPresentation(),
          selectedCity: $selectedCity,
          transitionNamespace: transitionNamespace,
          onOpenMapDetail: {},
          feedbackMessage: nil,
          feedbackFact: nil,
          feedbackIsFinished: false,
          onDismissFeedback: {})
      }
    }
    .background(CityChainPalette.paper)
  }
}

#Preview("Pocket Atlas — Austin to Nashville") {
  CityAtlasRoutePreview()
}

#Preview("Pocket Atlas detail — Austin to Nashville") {
  CityAtlasRoutePreview(showsDetail: true)
}

private extension View {
  @ViewBuilder
  func aspectRatio(_ ratio: CGFloat, contentMode: ContentMode, isEnabled: Bool) -> some View {
    if isEnabled {
      aspectRatio(ratio, contentMode: contentMode)
    } else {
      self
    }
  }
}
