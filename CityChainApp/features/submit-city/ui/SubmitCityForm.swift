import SwiftUI

struct SubmitCityForm: View {
  @Binding var text: String
  @FocusState private var isFocused: Bool
  @ScaledMetric(relativeTo: .title2) private var buttonSize = 52
  let isDisabled: Bool
  let isSubmitting: Bool
  let onSubmit: (String) async -> Bool

  var body: some View {
    let cannotSubmit = isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    HStack(spacing: 12) {
      TextField("Your city name", text: $text, axis: .vertical)
        .font(.title3.weight(.medium))
        .textFieldStyle(.plain)
        .lineLimit(1...3)
        .focused($isFocused)
        .disabled(isDisabled)
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
              .tint(CityChainPalette.blue)
          } else {
            Image(systemName: "arrow.up")
              .font(.title2.weight(.heavy))
          }
        }
        .frame(width: buttonSize, height: buttonSize)
        .background(cannotSubmit ? CityChainPalette.sky : CityChainPalette.blue, in: Circle())
        .foregroundStyle(cannotSubmit ? CityChainPalette.secondaryInk : .white)
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(cannotSubmit)
      .accessibilityLabel("Send city")
      .frame(minWidth: 52, minHeight: 52)
    }
    .padding(.leading, 18)
    .padding(.trailing, 7)
    .padding(.vertical, 7)
    .background(.white, in: RoundedRectangle(cornerRadius: 33))
    .overlay(
      RoundedRectangle(cornerRadius: 33).strokeBorder(
        isFocused ? CityChainPalette.blue : CityChainPalette.ink.opacity(0.08),
        lineWidth: isFocused ? 2 : 1)
    )
    .shadow(color: CityChainPalette.ink.opacity(0.08), radius: 16, y: 6)
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .frame(maxWidth: 560)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial)
  }

  private func submit() {
    let cityName = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isDisabled, !cityName.isEmpty else { return }
    Task { @MainActor in
      if await onSubmit(cityName) {
        text = ""
        isFocused = false
      }
    }
  }
}
