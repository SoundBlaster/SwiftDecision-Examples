import SwiftUI
import OracleHistory
import OracleGame

struct OraclePipelineDetailView: View {
  let entry: OracleHistoryEntry

  var body: some View {
    List {
      Section(header: Text("Question and answer")) {
        detailValue("Question", value: entry.question)
        detailValue("Answer", value: entry.answer, tint: .oracleLavender)
        detailValue("Decision", value: entry.mode)
        detailValue("Provider", value: entry.source)
        detailValue("Timestamp", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
      }

      if let pipeline = entry.pipeline, !pipeline.isEmpty {
        ForEach(pipeline) { stage in
          Section(header: Text(stage.title)) {
            if let summary = stage.summary {
              Label(summary, systemImage: "info.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.oracleLavender)
            }

            ForEach(stage.details ?? []) { detail in
              HStack(alignment: .top, spacing: 10) {
                Text(detail.label)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .frame(width: 120, alignment: .leading)
                Text(detail.value)
                  .font(.caption.weight(.medium))
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .accessibilityElement(children: .combine)
            }

            if let orderedTrace = stage.orderedTrace, !orderedTrace.isEmpty {
              Text("Ordered within this decision call")
                .font(.caption)
                .foregroundStyle(.secondary)
              ForEach(orderedTrace) { event in
                timelineRow(event, events: orderedTrace)
              }
            } else {
              ForEach(Array(stage.decisionEvents.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 10) {
                  Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.oracleLavender)
                    .frame(width: 18)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(event.stage.pipelineDisplayName)
                      .font(.subheadline)
                    if let detail = event.detail, !detail.isEmpty {
                      Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                  Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
              }

              ForEach(Array(stage.specificationEvents.enumerated()), id: \.offset) { index, event in
                specificationRow(event, depth: depth(of: event, in: stage.specificationEvents))
                  .id("\(stage.id)-\(index)")
              }
            }

            if stage.decisionEvents.isEmpty && stage.specificationEvents.isEmpty && (stage.orderedTrace?.isEmpty ?? true) {
              Label("No trace events", systemImage: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      } else {
        Section(header: Text("Decision pipeline")) {
          VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
              .font(.title2)
            Text("No trace saved")
              .font(.headline)
            Text("This history item was created before decision tracing was enabled.")
              .font(.caption)
              .multilineTextAlignment(.center)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationBarTitle("Decision pipeline", displayMode: .inline)
    .navigationBarHidden(false)
  }

  private func detailValue(_ title: String, value: String, tint: Color = .primary) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.body)
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 2)
  }

  private func specificationRow(_ event: OracleSpecificationTraceStep, depth: Int) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol(for: event.outcome))
        .foregroundStyle(color(for: event.outcome))
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(event.name.pipelineDisplayName)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          Text(event.outcome)
          Text(event.durationNanoseconds.pipelineDuration)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, CGFloat(depth) * 16)
    .accessibilityElement(children: .combine)
  }

  private func timelineRow(
    _ event: OraclePipelineTimelineEvent,
    events: [OraclePipelineTimelineEvent]
  ) -> some View {
    let isSpecification = event.kind == .specification
    let kind = isSpecification ? "Rule check" : "Flow"
    var metadata = [kind]
    if let outcome = event.outcome { metadata.append(outcome) }
    if let duration = event.durationNanoseconds { metadata.append(duration.pipelineDuration) }
    metadata.append("at +\(event.elapsedNanoseconds.pipelineOffset)")

    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: isSpecification ? symbol(for: event.outcome ?? "") : lifecycleSymbol(for: event.name))
        .foregroundStyle(isSpecification ? color(for: event.outcome ?? "") : Color.oracleLavender)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(event.name.pipelineDisplayName)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
        Text(metadata.joined(separator: " · "))
          .font(.caption2)
          .foregroundStyle(.secondary)
        if let detail = event.detail, !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, CGFloat(depth(of: event, in: events)) * 14)
    .accessibilityElement(children: .combine)
  }

  private func depth(of event: OraclePipelineTimelineEvent, in events: [OraclePipelineTimelineEvent]) -> Int {
    let parents = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.parentID) })
    var depth = 0
    var parent = event.parentID
    var visited: Set<UInt64> = []
    while let id = parent, visited.insert(id).inserted {
      depth += 1
      parent = parents[id] ?? nil
    }
    return depth
  }

  private func lifecycleSymbol(for name: String) -> String {
    switch name {
    case "Request validated", "Output validated": "checkmark.seal"
    case "Policy selected": "arrow.triangle.branch"
    case "Inference started", "Inference completed": "sparkles"
    case "Decision resolved": "arrow.uturn.forward"
    default: "point.3.connected.trianglepath.dotted"
    }
  }

  private func depth(of event: OracleSpecificationTraceStep, in events: [OracleSpecificationTraceStep]) -> Int {
    let parents = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.parentID) })
    var depth = 0
    var parent = event.parentID
    var visited: Set<Int> = []
    while let id = parent, visited.insert(id).inserted {
      depth += 1
      parent = parents[id] ?? nil
    }
    return depth
  }

  private func symbol(for outcome: String) -> String {
    switch outcome {
    case "Satisfied", "Selected": "checkmark.circle.fill"
    case "Not satisfied", "No match": "xmark.circle"
    case "Skipped": "forward.end.circle"
    case "Cancelled": "xmark.circle.fill"
    default: outcome.hasPrefix("Failed") ? "exclamationmark.circle.fill" : "circle"
    }
  }

  private func color(for outcome: String) -> Color {
    switch outcome {
    case "Satisfied", "Selected": .green
    case "Not satisfied", "No match", "Skipped": .secondary
    case "Cancelled": .orange
    default: outcome.hasPrefix("Failed") ? .red : .secondary
    }
  }
}

private extension String {
  var pipelineDisplayName: String {
    enumerated().reduce(into: "") { result, pair in
      let character = pair.element
      if character.isUppercase, pair.offset > 0 {
        result.append(" ")
      }
      result.append(character)
    }
  }
}

private extension UInt64 {
  var pipelineDuration: String {
    let milliseconds = Double(self) / 1_000_000
    if milliseconds < 1 {
      return "<1 ms"
    }
    return String(format: "%.1f ms", milliseconds)
  }

  var pipelineOffset: String {
    let milliseconds = Double(self) / 1_000_000
    if milliseconds < 1 {
      return String(format: "%.0f μs", Double(self) / 1_000)
    }
    return String(format: "%.1f ms", milliseconds)
  }
}
