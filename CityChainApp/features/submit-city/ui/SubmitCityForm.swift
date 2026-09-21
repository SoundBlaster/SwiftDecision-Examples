import SwiftUI

struct SubmitCityForm: View {
  let isDisabled: Bool
  let isSubmitting: Bool
  let onSubmit: (String) async -> Bool

  @State private var cityName = ""

  var body: some View {
    HStack {
      TextField("Enter any US city", text: $cityName)
        .textFieldStyle(.roundedBorder)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.go)
        .onSubmit(submit)
        .accessibilityLabel("US city")

      Button(action: submit) {
        if isSubmitting {
          ProgressView()
            .frame(minWidth: 28, minHeight: 28)
        } else {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title)
            .symbolRenderingMode(.hierarchical)
        }
      }
      .buttonStyle(.plain)
      .disabled(isDisabled || cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Submit city")
    }
    .padding()
    .frame(maxWidth: 640)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial)
  }

  private func submit() {
    let city = cityName
    guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    Task { @MainActor in
      if await onSubmit(city) {
        cityName = ""
      }
    }
  }
}
