import CityChainGame
import SwiftUI

struct CityAtlasMapView: View {
  static let transitionSourceID = "city-atlas-map"

  let visitedCities: [USCity]
  let presentation: ScoutPresentation
  @Binding var selectedCity: USCity?
  let transitionNamespace: Namespace.ID
  let onOpenMapDetail: () -> Void
  let feedbackMessage: String?
  let feedbackIsFinished: Bool
  let onDismissFeedback: () -> Void

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
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 10) {
          ScoutView(presentation: presentation)
            .frame(width: 52, height: 52)
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
          Group {
            if #available(iOS 18.0, *) {
              mapCanvas(data: mapData)
                .matchedTransitionSource(id: Self.transitionSourceID, in: transitionNamespace)
            } else {
              mapCanvas(data: mapData)
            }
          }

          if let feedbackMessage {
            CityTurnFeedbackView(
              message: feedbackMessage,
              presentation: presentation,
              isFinished: feedbackIsFinished,
              onDismiss: onDismissFeedback)
          }

          if let selectedCity {
            SelectedAtlasCityCard(
              city: selectedCity, isLatest: selectedCity.id == visitedCities.last?.id)
            if mapData.point(for: selectedCity) == nil {
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

          if availableMarkers.count > 1 {
            ScrollView(.horizontal) {
              HStack(spacing: 8) {
                ForEach(availableMarkers, id: \.point.id) { marker in
                  Button {
                    selectedCity = marker.city
                  } label: {
                    Text(marker.city.name)
                      .font(.caption.weight(.semibold))
                      .padding(.horizontal, 11)
                      .padding(.vertical, 8)
                      .background(
                        selectedCity?.id == marker.city.id ? CityChainPalette.sky : .white,
                        in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .accessibilityHint("Shows this visited city on the map")
                }
              }
            }
            .scrollIndicators(.hidden)
          }
        } else {
          ContentUnavailableView(
            "Atlas map unavailable",
            systemImage: "map",
            description: Text("Use the searchable city list while the offline map is unavailable."))
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 25))
      .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(CityChainPalette.ink.opacity(0.07)))
    }
    .scrollIndicators(.hidden)
    .contentMargins(.top, 18, for: .scrollContent)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func mapCanvas(data: CityAtlasMapData) -> some View {
    CityAtlasMapCanvas(
      data: data, markers: availableMarkers, routeSegments: routeSegments,
      selectedCity: selectedCity,
      visitedStates: Set(visitedCities.compactMap(\.stateAbbreviation)),
      latestState: visitedCities.last?.stateAbbreviation,
      onSelect: { selectedCity = $0 },
      onOpenMapDetail: onOpenMapDetail)
      .frame(height: 300)
      .accessibilityLabel("Map of the United States with separately labeled Alaska and Hawaii insets")
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

  var body: some View {
    GeometryReader { geometry in
      let layout = AtlasMapFrames(size: geometry.size)
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          for state in data.states {
            var path = Path()
            path.addPath(state.simplePath, transform: layout.transform(for: state.region))
            let fill = state.abbreviation == latestState
              ? CityChainPalette.orange.opacity(0.75)
              : (visitedStates.contains(state.abbreviation)
                ? CityChainPalette.mint.opacity(0.9)
                : CityChainPalette.sky.opacity(0.62))
            context.fill(path, with: .color(fill), style: FillStyle(eoFill: true))
            context.stroke(path, with: .color(CityChainPalette.blue.opacity(0.42)), lineWidth: 0.8)
          }
          for segment in routeSegments {
            let from = data.projectedPoint(for: segment.from)
            let to = data.projectedPoint(for: segment.to)
            guard from.region == segment.region, to.region == segment.region else { continue }
            var path = Path()
            path.move(to: layout.project(from.point, for: segment.region))
            path.addLine(to: layout.project(to.point, for: segment.region))
            context.stroke(
              path,
              with: .color(CityChainPalette.teal.opacity(0.8)),
              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
          }
        }
        .accessibilityHidden(true)

        if let onOpenMapDetail {
          Button(action: onOpenMapDetail) {
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

        Text("UNITED STATES")
          .font(.system(.caption2, design: .rounded, weight: .bold))
          .tracking(1.1)
          .foregroundStyle(CityChainPalette.secondaryInk)
          .position(x: layout.mainland.midX, y: layout.mainland.maxY - 6)
          .accessibilityHidden(true)
          .allowsHitTesting(false)

        ForEach(markers, id: \.point.id) { marker in
          let projected = data.projectedPoint(for: marker.point)
          let position = layout.project(projected.point, for: projected.region)
          Button {
            onSelect(marker.city)
          } label: {
            Image(systemName: selectedCity?.id == marker.city.id ? "mappin.circle.fill" : "circle.fill")
              .font(.system(size: selectedCity?.id == marker.city.id ? 25 : 11, weight: .bold))
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, CityChainPalette.blue)
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .position(position)
          .accessibilityLabel("\(marker.city.name), \(marker.city.stateName ?? "United States")")
          .accessibilityHint("Shows this visited city on the map")
        }

        AtlasInsetLabel(title: "Alaska", abbreviation: "AK")
          .position(x: layout.alaska.minX + 39, y: layout.alaska.minY + 16)
          .allowsHitTesting(false)
        AtlasInsetLabel(title: "Hawaii", abbreviation: "HI")
          .position(x: layout.hawaii.minX + 39, y: layout.hawaii.minY + 16)
          .allowsHitTesting(false)
      }
      .background(CityChainPalette.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
      .clipShape(RoundedRectangle(cornerRadius: 18))
    }
  }
}

private struct AtlasInsetLabel: View {
  let title: String
  let abbreviation: String

  var body: some View {
    VStack(spacing: 1) {
      Text(title)
        .font(.caption2.weight(.bold))
        .foregroundStyle(CityChainPalette.ink)
      Text(abbreviation)
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .foregroundStyle(CityChainPalette.secondaryInk)
    }
    .padding(4)
    .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 7))
    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(CityChainPalette.ink.opacity(0.16)))
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

struct CityAtlasMapDetailView: View {
  let visitedCities: [USCity]
  let presentation: ScoutPresentation
  @Binding var selectedCity: USCity?
  @Environment(\.dismiss) private var dismiss

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
            ScoutView(presentation: presentation)
              .frame(width: 48, height: 48)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
              Text("Pocket Atlas")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CityChainPalette.ink)
              Text("Tap a city marker to inspect that stop.")
                .font(.subheadline)
                .foregroundStyle(CityChainPalette.secondaryInk)
            }
            Spacer(minLength: 8)
            Button {
              dismiss()
            } label: {
              Label("Close", systemImage: "xmark")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 6)
                .background(CityChainPalette.paper, in: Capsule())
            }
            .buttonStyle(.plain)
          }

          if let mapData {
            CityAtlasMapCanvas(
              data: mapData, markers: markers, routeSegments: routeSegments,
              selectedCity: selectedCity,
              visitedStates: Set(visitedCities.compactMap(\.stateAbbreviation)),
              latestState: visitedCities.last?.stateAbbreviation,
              onSelect: { selectedCity = $0 })
              .frame(height: min(max(260, geometry.size.height * 0.62), 640))
              .accessibilityLabel("Interactive map of the United States with Alaska and Hawaii insets")

            if let selectedCity {
              SelectedAtlasCityCard(
                city: selectedCity, isLatest: selectedCity.id == visitedCities.last?.id)
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
      .background(CityChainPalette.paper)
    }
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
  }
}

private struct AtlasMapFrames {
  let mainland: CGRect
  let alaska: CGRect
  let hawaii: CGRect

  init(size: CGSize) {
    let insetHeight = max(62, size.height * 0.24)
    let gap: CGFloat = 8
    mainland = CGRect(x: 9, y: 8, width: size.width - 18, height: size.height - insetHeight - 22)
    alaska = CGRect(
      x: 10, y: size.height - insetHeight - 8,
      width: (size.width - 28) * 0.6, height: insetHeight - 2)
    hawaii = CGRect(
      x: alaska.maxX + gap, y: alaska.minY,
      width: size.width - alaska.maxX - gap - 10, height: insetHeight - 2)
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

  private func fittedFrame(for region: CityAtlasMapData.Region) -> CGRect {
    let container = frame(for: region)
    let bounds = CityAtlasMapData.bounds(for: region)
    let centerLatitude = (bounds.north + bounds.south) / 2 * .pi / 180
    let aspect = CGFloat((bounds.east - bounds.west) * cos(centerLatitude)
      / (bounds.north - bounds.south))
    let width = container.width / container.height > aspect ? container.height * aspect : container.width
    let height = width / aspect
    return CGRect(
      x: container.midX - width / 2, y: container.midY - height / 2,
      width: width, height: height)
  }
}
