import NestedA11yIDs
import OracleGame
import SwiftUI

/// Provider choice is independent from saving or clearing a Jev credential.
struct OracleInferenceSettings: View {
  @Binding var provider: OracleInferenceProvider
  @Binding var normalizesAppleOutput: Bool
  let providerDescription: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Inference provider")
        Spacer()
        Picker("Inference provider", selection: $provider) {
          Text("Jev").tag(OracleInferenceProvider.jev)
          Text("Apple Intelligence").tag(OracleInferenceProvider.appleIntelligence)
          Text("None").tag(OracleInferenceProvider.none)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .nestedAccessibilityIdentifier("provider")
      }

      Text(providerDescription)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .nestedAccessibilityIdentifier("provider-status")

      if provider == .appleIntelligence {
        Text("Local pilot · requests stay on this device. Estimates are not calibrated probabilities. Unavailable or invalid output is reported without switching providers.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Normalize Apple output", isOn: $normalizesAppleOutput)
          .nestedAccessibilityIdentifier("normalize-apple-output")
        Text("On: normalize relative weights. Off: require probabilities that already sum to 1.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if provider == .none {
        Text("No AI requests. Oracle uses its offline answer engine; an empty question still gives a random answer.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
