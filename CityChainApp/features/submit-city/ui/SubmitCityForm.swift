import SwiftUI

struct SubmitCityForm: View {
  @Binding var text: String
  let isDisabled: Bool
  let isSubmitting: Bool
  let onSubmit: (String) async -> Bool

  var body: some View {
    HStack(spacing: 12) {
      TextField("Type a city from the atlas", text: $text)
        .font(.title3.weight(.medium))
        .textFieldStyle(.plain)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.go)
        .onSubmit(submit)
        .accessibilityLabel("City name")
        .accessibilityHint("Enter a city from the U.S. atlas")

      Button(action: submit) {
        Group {
          if isSubmitting {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: "arrow.up")
              .font(.title2.weight(.heavy))
          }
        }
        .frame(width: 52, height: 52)
        .background(CityChainPalette.orange, in: Circle())
        .foregroundStyle(.white)
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Send city")
      .frame(minWidth: 52, minHeight: 52)
    }
    .padding(.leading, 18)
    .padding(.trailing, 7)
    .padding(.vertical, 7)
    .background(.white, in: Capsule())
    .overlay(Capsule().stroke(CityChainPalette.blue.opacity(0.16), lineWidth: 1))
    .shadow(color: CityChainPalette.ink.opacity(0.12), radius: 16, y: 6)
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .frame(maxWidth: 560)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial)
  }

  private func submit() {
    let cityName = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cityName.isEmpty else { return }
    Task { @MainActor in
      if await onSubmit(cityName) {
        text = ""
      }
    }
  }
}
