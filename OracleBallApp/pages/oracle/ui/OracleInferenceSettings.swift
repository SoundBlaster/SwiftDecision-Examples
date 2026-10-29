import CoreTransferable
import OracleGLiNER
import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Explicit provider selection and separately provisioned local model controls.
struct OracleInferenceSettings: View {
  let model: OraclePageModel
  let onShowInstallationLog: () -> Void
  @State private var isSelectingFolder = false
  @State private var showsModelSetup = false

  var body: some View {
    Section("Inference") {
      Button {
        model.selectProvider(.none)
        showsModelSetup = false
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Offline simulation")
            Text("Use the app without a local AI model.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          if model.provider == .none { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(model.isPreparingModel)
      .accessibilityIdentifier("oracle.settings.provider.none")

      if model.supportsGLiNER {
        Button {
          showsModelSetup = true
          if model.isModelInstalled, model.provider != .gliner { model.selectProvider(.gliner) }
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("On-device AI")
              Text(model.isModelInstalled ? "GLiNER small · Installed" : "GLiNER small · Not installed")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.provider == .gliner { Image(systemName: "checkmark").foregroundStyle(.tint) }
            else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isPreparingModel)
        .accessibilityIdentifier("oracle.settings.provider.gliner")
      }

        #if DEBUG && ORACLE_JEV
      Button("Jev") { model.selectProvider(.jev) }
        .disabled(model.isPreparingModel)
        #endif
      if model.supportsGLiNER && (showsModelSetup || model.provider == .gliner || model.isPreparingModel || model.modelIssue != nil) {
          if !model.isModelInstalled {
            Text("Experimental English model. Questions are processed on this device. Download about 70 MB; the model uses about 87 MB of storage.")
              .font(.caption).foregroundStyle(.secondary)
            if model.isDownloadingModel || model.isPreparingModel {
              OracleModelDownloadStatus(isDownloading: model.isDownloadingModel,
                                        progress: model.modelDownloadProgress)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
              if model.isDownloadingModel {
                Button("Cancel download", action: model.cancelHostedModelInstallation)
              }
            } else {
              Button(model.modelIssue == nil ? "Download model" : "Try again", action: model.installHostedGLiNERModel)
                .accessibilityIdentifier("oracle.settings.gliner-install")
            }
          } else {
          if model.isPreparingModel {
            OracleModelDownloadStatus(isDownloading: model.isDownloadingModel,
                                      progress: model.modelDownloadProgress)
          }
          if let issue = model.providerIssue {
            Text(issue).font(.caption).foregroundStyle(.secondary)
          }
          Text("Experimental English model. Questions stay on this device. Estimates are not calibrated probabilities.")
            .font(.caption)
            .foregroundStyle(.secondary)
          DisclosureGroup("Advanced settings") {
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
            Button("Remove local model", role: .destructive, action: model.removeGLiNERModel)
              .disabled(model.isPreparingModel)
              .accessibilityIdentifier("oracle.settings.gliner-remove")
          }
          }
          Button(action: onShowInstallationLog) {
            Label("Model installation log", systemImage: "doc.text.magnifyingglass")
          }
          .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
          .accessibilityIdentifier("oracle.settings.gliner-log")
          DisclosureGroup("Developer import") {
          #if DEBUG
          Button("Download from GitHub", action: model.installDevelopmentGLiNERModel)
            .disabled(model.isPreparingModel || model.isModelInstalled)
            .accessibilityIdentifier("oracle.settings.gliner-github")
          Text("Development only. Download the same verified model from GitHub when Apple hosting is unavailable.")
            .font(.caption)
            .foregroundStyle(.secondary)
          #endif
          Button("Import model folder") { isSelectingFolder = true }
            .disabled(model.isPreparingModel)
            .accessibilityIdentifier("oracle.settings.gliner-import")
          Text("Choose the GLiNER small INT8 export folder in Files. About 87 MB is stored separately from the app and can be removed below.")
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          if let issue = model.modelIssue {
            Text(issue)
              .font(.caption)
              .foregroundStyle(.orange)
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

/// The same stable status layout in settings and in the installation journal.
private struct OracleModelDownloadStatus: View {
  let isDownloading: Bool
  let progress: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: isDownloading ? "arrow.down.circle" : "gearshape")
          .foregroundStyle(.tint)
          .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
          .accessibilityHidden(true)
        if !isDownloading {
          Text("Preparing local model…")
        } else if progress == nil {
          Text("Connecting to download…")
        } else {
          Text("Downloading local model…")
        }
        Spacer(minLength: 8)
        if isDownloading, let progress {
          Text(progress, format: .percent.precision(.fractionLength(0)))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      ProgressView(value: progress ?? 0)
        .opacity(!isDownloading && progress == nil ? 0.45 : 1)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}


/// A live diagnostic window with an immutable export snapshot on sharing.
struct OracleModelInstallationLogView: View {
  let model: OraclePageModel
  @Environment(\.dismiss) private var dismiss
  @State private var followsLatest = true
  @State private var didCopy = false

  private var entries: [OracleGLiNERInstallationLog.Entry] {
    model.installationLog.journal.entries
  }

  var body: some View {
    NavigationStack {
      VStack {
        if model.isDownloadingModel || model.isPreparingModel {
          OracleModelDownloadStatus(isDownloading: model.isDownloadingModel,
                                    progress: model.modelDownloadProgress)
          .padding(.horizontal)
        }
        ScrollViewReader { proxy in
          List {
            if entries.isEmpty {
              ContentUnavailableView("No installation events yet", systemImage: "doc.text")
            }
            ForEach(entries) { entry in
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, style: .time)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text(verbatim: entry.event.message)
                  .font(.system(.caption, design: .monospaced))
                  .foregroundStyle(entry.event.isFailure ? Color.orange : Color.primary)
                  .textSelection(.enabled)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .id(entry.id)
            }
          }
          .listStyle(.plain)
          .onChange(of: entries.last?.id) { _, id in
            if followsLatest, let id { proxy.scrollTo(id, anchor: .bottom) }
          }
          .onAppear {
            if let id = entries.last?.id { proxy.scrollTo(id, anchor: .bottom) }
          }
        }
        Toggle("Follow latest", isOn: $followsLatest)
          .padding(.horizontal)
        HStack {
          if model.isDownloadingModel {
            Button("Cancel download", action: model.cancelHostedModelInstallation)
          } else if !model.isModelInstalled {
            Button("Retry installation", action: model.installHostedGLiNERModel)
              .disabled(model.isPreparingModel)
          }
          Spacer()
          Button("Clear log", role: .destructive, action: model.installationLog.clear)
            .disabled(entries.isEmpty)
        }
        .padding()
      }
      .navigationTitle("Model installation log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            Button {
              UIPasteboard.general.string = model.installationLog.journal.text()
              didCopy = true
            } label: {
              Label(didCopy ? "Copied" : "Copy log", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("oracle.model-log.copy")
            ShareLink(item: OracleInstallationLogExport(log: model.installationLog.journal),
                      preview: SharePreview("Model installation log")) {
              Label("Export log", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("oracle.model-log.export")
          } label: {
            Label("Log actions", systemImage: "ellipsis.circle")
          }
          .disabled(entries.isEmpty)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .accessibilityIdentifier("oracle.model-log")
  }
}

private struct OracleInstallationLogExport: Transferable, Sendable {
  let log: OracleGLiNERInstallationLog

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .utf8PlainText) { item in
      Data(item.log.text().utf8)
    }
    .suggestedFileName { _ in "oracle-model-installation-log.txt" }
  }
}
