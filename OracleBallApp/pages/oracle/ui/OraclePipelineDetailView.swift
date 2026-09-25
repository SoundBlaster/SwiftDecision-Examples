import SwiftUI
import OracleHistory
import OracleGame
import NestedA11yIDs

struct OraclePipelineDetailView: View {
  let entry: OracleHistoryEntry

  var body: some View {
    List {
      Section(header: Text("Question and answer")) {
        detailValue(
          "Question",
          value: entry.question.isEmpty ? String(localized: "Random answer") : entry.question)
        detailValue("Answer", value: entry.answer, tint: .oracleLavender)
        detailValue("Decision", value: localizedPipelineText(entry.mode))
        detailValue("Provider", value: localizedPipelineText(entry.source))
        detailValue("Timestamp", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
      }

      if let pipeline = entry.pipeline, !pipeline.isEmpty {
        ForEach(pipeline) { stage in
          Section(header: Text(localizedPipelineText(stage.title))) {
            if let summary = stage.summary {
              Label {
                monospacedMetricText(localizedPipelineText(summary), style: .caption, weight: .medium)
              } icon: {
                Image(systemName: "info.circle")
              }
                .foregroundStyle(Color.oracleLavender)
            }

            ForEach(stage.details ?? []) { detail in
              HStack(alignment: .top, spacing: 10) {
                Text(localizedPipelineText(detail.label))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .frame(width: 120, alignment: .leading)
                monospacedMetricText(localizedDetailValue(detail), style: .caption, weight: .medium)
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
                    Text(localizedPipelineText(event.stage.pipelineDisplayName))
                      .font(.subheadline)
                    if let detail = event.detail, !detail.isEmpty {
                      monospacedMetricText(localizedPipelineText(detail), style: .caption)
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
    .a11yRoot("oracle.pipeline")
  }

  private func detailValue(_ title: String, value: String, tint: Color = .primary) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(localizedPipelineText(title))
        .font(.caption)
        .foregroundStyle(.secondary)
      if title == "Timestamp" || title == "Answer" {
        monospacedMetricText(value, style: .body)
          .foregroundStyle(tint)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(value)
          .font(.body)
          .foregroundStyle(tint)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 2)
    .nestedAccessibilityIdentifier(title.lowercased().replacingOccurrences(of: " ", with: "-"))
  }

  private func specificationRow(_ event: OracleSpecificationTraceStep, depth: Int) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol(for: event.outcome))
        .foregroundStyle(color(for: event.outcome))
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(localizedSpecificationDisplayName(event.name))
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          Text(localizedPipelineText(event.outcome))
          monospacedMetricText(event.durationNanoseconds.pipelineDuration, style: .caption2)
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
    var metadata = [localizedPipelineText(kind)]
    if let outcome = event.outcome { metadata.append(localizedPipelineText(outcome)) }
    if let duration = event.durationNanoseconds { metadata.append(duration.pipelineDuration) }
    metadata.append(String(format: String(localized: "at +%@"), locale: .current, event.elapsedNanoseconds.pipelineOffset))

    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: isSpecification ? symbol(for: event.outcome ?? "") : lifecycleSymbol(for: event.name))
        .foregroundStyle(isSpecification ? color(for: event.outcome ?? "") : Color.oracleLavender)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(isSpecification ? localizedSpecificationDisplayName(event.name) : localizedPipelineText(event.name.pipelineDisplayName))
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
        monospacedMetricText(metadata.joined(separator: " · "), style: .caption2)
          .foregroundStyle(.secondary)
        if let detail = event.detail, !detail.isEmpty {
          monospacedMetricText(localizedPipelineText(detail), style: .caption)
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
    case "Request validated", "Output validated", "Запрос проверен", "Результат проверен": "checkmark.seal"
    case "Policy selected", "Выбрана политика": "arrow.triangle.branch"
    case "Inference started", "Inference completed", "Начат вывод", "Вывод завершён": "sparkles"
    case "Decision resolved", "Решение получено": "arrow.uturn.forward"
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
    case "Satisfied", "Selected", "Выполнено", "Выбрано": "checkmark.circle.fill"
    case "Not satisfied", "No match", "Не выполнено", "Нет совпадения": "xmark.circle"
    case "Skipped", "Пропущено": "forward.end.circle"
    case "Cancelled", "Отменено": "xmark.circle.fill"
    default: isFailedOutcome(outcome) ? "exclamationmark.circle.fill" : "circle"
    }
  }

  private func color(for outcome: String) -> Color {
    switch outcome {
    case "Satisfied", "Selected", "Выполнено", "Выбрано": .green
    case "Not satisfied", "No match", "Skipped", "Не выполнено", "Нет совпадения", "Пропущено": .secondary
    case "Cancelled", "Отменено": .orange
    default: isFailedOutcome(outcome) ? .red : .secondary
    }
  }

  private func isFailedOutcome(_ outcome: String) -> Bool {
    outcome.hasPrefix("Failed") || outcome.hasPrefix("Ошибка:")
  }
}

private func localizedPipelineText(_ value: String) -> String {
  if let match = value.range(of: #"^(\d+) options extracted$"#, options: .regularExpression),
     let count = Int(value[match].split(separator: " ").first ?? "") {
    return String(format: String(localized: "%d options extracted"), locale: .current, count)
  }

  if let match = value.range(of: #"^Найдено вариантов: (\d+)$"#, options: .regularExpression),
     let count = value[match].split(separator: " ").last.flatMap({ Int($0) }) {
    return String(format: String(localized: "%d options extracted"), locale: .current, count)
  }

  if value.hasPrefix("Failed: ") || value.hasPrefix("Ошибка: ") {
    let message = String(value.drop(while: { $0 != ":" }).dropFirst().drop(while: { $0 == " " }))
    return String(format: String(localized: "Failed: %@"), locale: .current, message)
  }

  if value.hasPrefix("Split on ‘"), value.hasSuffix("’") {
    let separator = String(value.dropFirst("Split on ‘".count).dropLast())
    return String(format: String(localized: "Split on ‘%@’"), locale: .current, separator)
  }

  if value.contains(" · ") {
    return value
      .components(separatedBy: " · ")
      .map(localizedPipelineText)
      .joined(separator: " · ")
  }

  if let legacyKey = legacyRussianPipelineKeys[value] {
    return String(localized: String.LocalizationValue(legacyKey))
  }

  if let match = value.range(of: #"^(.*?)\s+(\d+(?:[.,]\d+)?%)$"#, options: .regularExpression) {
    let pieces = value[match].split(separator: " ", maxSplits: 1)
    if pieces.count == 2 {
      let label = String(localized: String.LocalizationValue(String(pieces[0])))
      return "\(label) \(pieces[1])"
    }
  }

  return String(localized: String.LocalizationValue(value))
}

private let legacyRussianPipelineKeys: [String: String] = [
  "Проверка запроса": "request validation",
  "проверка запроса": "request validation",
  "Маршрутизация по политике": "policy routing",
  "маршрутизация по политике": "policy routing",
  "Ответ модели": "backend prediction",
  "ответ модели": "backend prediction",
  "Проверка результата": "output validation",
  "проверка результата": "output validation",
  "Минимальная вероятность": "minimum probability",
  "Минимальная уверенность": "minimum confidence",
  "Политика принятия": "acceptance policy",
  "Асинхронное условие": "async predicate",
  "Допустимость вопроса": "question eligibility",
  "Проверка допустимости вопроса": "Question eligibility",
  "Варианты выбора": "Choice alternatives",
  "Маршрутизация запроса": "Request routing",
  "Тип вопроса": "Question type",
  "Выбор ответа": "Answer resolution",
  "Проверка ответа": "Answer validation",
  "Запрос проверен": "Request validated",
  "Выбрана политика": "Policy selected",
  "Начат вывод": "Inference started",
  "Вывод завершён": "Inference completed",
  "Результат проверен": "Output validated",
  "Решение получено": "Decision resolved",
  "Результат правила": "Rule result",
  "Проверка правила": "Rule check",
  "Этап процесса": "Flow",
  "Выполнено": "Satisfied",
  "Не выполнено": "Not satisfied",
  "Выбрано": "Selected",
  "Нет совпадения": "No match",
  "Пропущено": "Skipped",
  "Пропущена": "Skipped",
  "Отменено": "Cancelled",
  "Запрошен неподдерживаемый режим ответа": "unsupported answer mode requested",
  "Вопрос не относится к поддерживаемым типам ответа": "question is outside the supported answer types",
  "Не удалось извлечь варианты ответа": "choice alternatives could not be extracted",
  "Варианты не найдены": "No options extracted",
  "Да / Нет": "Noul",
  "Выбор": "Choice",
  "Оценка": "Score",
  "Автоматически": "Automatic",
  "Принят": "Accepted",
  "Выбран запасной ответ": "Fallback selected",
  "Использован запасной ответ": "Fallback used",
  "Числовые варианты возраста": "Age-number alternatives",
  "Варианты разделены запятыми": "Comma-separated alternatives",
  "Ответ доступен": "Answer available",
  "Запрошенный режим": "Requested mode",
  "Выбранный маршрут": "Selected route",
  "Причина": "Reason",
  "Уверенность выбора": "Selected confidence",
  "Доступен проверенный ответ; запасной ответ не использовался.": "A validated answer was available and no fallback was used.",
  "Политика решения выбрала запасной ответ.": "The decision policy selected a fallback.",
]

private func localizedDetailValue(_ detail: OraclePipelineDetail) -> String {
  switch detail.id {
  case "requested-mode", "selected-route", "answer-available", "fallback-used", "answer-type",
       "resolution-reason", "validation-reason", "extraction-rule", "intent-scores", "probabilities":
    localizedPipelineText(detail.value)
  default:
    detail.value
  }
}

private func localizedSpecificationDisplayName(_ name: String) -> String {
  if name.contains("Any Async Specification"), name.contains("Oracle Request") {
    return localizedPipelineText("Oracle request rules")
  }
  return localizedPipelineText(name.pipelineDisplayName)
}

private func monospacedMetricText(
  _ value: String,
  style: Font.TextStyle,
  weight: Font.Weight = .regular
) -> Text {
  var attributed = AttributedString(value)
  let pattern = #"(?<![\p{L}\p{N}_])(?:[<>≤≥]\s*)?\d+(?:[ \u00A0\u202F]\d{3})*(?:[.,]\d+)?(?:\s*(?:ms|μs|µs|us|%|options?|мс|мкс|с|вариант(?:а|ов)?))?(?![\p{L}\p{N}_])"#
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return Text(value).font(.system(style, weight: weight))
  }

  let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
  for match in matches {
    guard
      let stringRange = Range(match.range, in: value),
      let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attributed),
      let upperBound = AttributedString.Index(stringRange.upperBound, within: attributed)
    else {
      continue
    }
    attributed[lowerBound..<upperBound].font = .system(style, design: .monospaced).weight(weight)
  }

  return Text(attributed).font(.system(style, weight: weight))
}

private extension String {
  var pipelineDisplayName: String {
    let displayName = enumerated().reduce(into: "") { result, pair in
      let character = pair.element
      if character.isUppercase, pair.offset > 0 {
        result.append(" ")
      }
      result.append(character)
    }
    guard let firstCharacter = displayName.first else { return displayName }
    return firstCharacter.uppercased() + displayName.dropFirst()
  }
}

private extension UInt64 {
  var pipelineDuration: String {
    let milliseconds = Double(self) / 1_000_000
    if milliseconds < 1 {
      return "<1 ms"
    }
    return String(format: "%.1f ms", locale: .current, milliseconds)
  }

  var pipelineOffset: String {
    let milliseconds = Double(self) / 1_000_000
    if milliseconds < 1 {
      return String(format: "%.0f μs", locale: .current, Double(self) / 1_000)
    }
    return String(format: "%.1f ms", locale: .current, milliseconds)
  }
}
