import OracleGLiNER
import SwiftUI
import UniformTypeIdentifiers

/// Explicit provider selection and separately provisioned local model controls.
struct OracleInferenceSettings: View {
  let model: OraclePageModel
  @State private var isSelectingFolder = false

  var body: some View {
    Section("Inference") {
      Picker("Provider", selection: Binding(get: { model.provider }, set: model.selectProvider)) {
        Text("Jev").tag(OracleInferenceProvider.jev)
        if model.supportsGLiNER && model.isGLiNERPilotEnabled {
          Text("GLiNER small").tag(OracleInferenceProvider.gliner)
        }
        Text("None").tag(OracleInferenceProvider.none)
      }
      .disabled(model.isPreparingModel)
      .accessibilityIdentifier("oracle.settings.provider")

      Text(model.providerDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("oracle.settings.provider-status")

      if model.supportsGLiNER {
        Toggle("Enable GLiNER pilot", isOn: Binding(
          get: { model.isGLiNERPilotEnabled }, set: model.setGLiNERPilotEnabled))
          .disabled(model.isPreparingModel)
          .accessibilityIdentifier("oracle.settings.gliner-pilot")

        if model.isGLiNERPilotEnabled {
          Text("Experimental English model. Questions stay on this device. Estimates are not calibrated probabilities.")
            .font(.caption)
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("GLiNER confidence threshold")
              Spacer()
              Text(model.glinerMinimumConfidence, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
            }
            Slider(value: Binding(get: { model.glinerMinimumConfidence },
                                  set: model.setGLiNERMinimumConfidence), in: 0 ... 1, step: 0.05)
              .accessibilityLabel("GLiNER confidence threshold")
              .accessibilityIdentifier("oracle.settings.gliner-confidence")
            HStack(spacing: 0) {
              ForEach(0 ... 20, id: \.self) { tick in
                Rectangle().frame(width: 1, height: tick.isMultiple(of: 5) ? 8 : 4)
                  .frame(maxWidth: .infinity)
              }
            }
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            HStack {
              Text("0%")
              Spacer()
              Text("100%")
            }
            .font(.caption)
            Text("Distribution confidence, not the winning weight. Lower values allow closer results. The winning weight must still reach 55%. Default: 5%.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .disabled(model.isSubmitting || model.isPreparingModel)
          Text(model.isModelInstalled ? "Local model installed" : "Local model not installed")
            .font(.subheadline)
            .accessibilityIdentifier("oracle.settings.gliner-model-status")
          if model.isPreparingModel {
            ProgressView("Preparing local model…")
          }
          Button("Import model folder") { isSelectingFolder = true }
            .disabled(model.isPreparingModel)
            .accessibilityIdentifier("oracle.settings.gliner-import")
          Text("Choose the GLiNER small INT8 export folder in Files. About 87 MB is stored separately from the app and can be removed below.")
            .font(.caption)
            .foregroundStyle(.secondary)
          if model.isModelInstalled {
            Button("Remove local model", role: .destructive, action: model.removeGLiNERModel)
              .disabled(model.isPreparingModel)
              .accessibilityIdentifier("oracle.settings.gliner-remove")
          }
          if let issue = model.modelIssue {
            Text(issue)
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }
    }
    .fileImporter(isPresented: $isSelectingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
      switch result {
      case let .success(urls):
        if let directory = urls.first { model.importGLiNERModel(from: directory) }
      case let .failure(error):
        if (error as NSError).code != CocoaError.userCancelled.rawValue { model.reportModelImportFailure() }
      }
    }
  }
}
