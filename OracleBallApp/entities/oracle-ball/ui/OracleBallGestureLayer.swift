import SwiftUI
import UIKit

/// UIKit's pan recognizer lets the ball interaction explicitly accept one touch only.
struct OracleBallGestureLayer: UIViewRepresentable {
  let onTap: () -> Void
  let onDragBegan: () -> Void
  let onDragChanged: (CGPoint, CGSize) -> Void
  let onDragEnded: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onTap: onTap,
      onDragBegan: onDragBegan,
      onDragChanged: onDragChanged,
      onDragEnded: onDragEnded)
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.backgroundColor = .clear
    view.isMultipleTouchEnabled = true

    let tap = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap))
    tap.numberOfTouchesRequired = 1
    tap.cancelsTouchesInView = false
    let pan = UIPanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handlePan(_:)))
    pan.minimumNumberOfTouches = 1
    pan.maximumNumberOfTouches = 1
    pan.cancelsTouchesInView = false
    tap.require(toFail: pan)
    view.addGestureRecognizer(tap)
    view.addGestureRecognizer(pan)
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.onTap = onTap
    context.coordinator.onDragBegan = onDragBegan
    context.coordinator.onDragChanged = onDragChanged
    context.coordinator.onDragEnded = onDragEnded
  }

  @MainActor
  final class Coordinator: NSObject {
    var onTap: () -> Void
    var onDragBegan: () -> Void
    var onDragChanged: (CGPoint, CGSize) -> Void
    var onDragEnded: () -> Void
    private var isDragging = false

    init(
      onTap: @escaping () -> Void,
      onDragBegan: @escaping () -> Void,
      onDragChanged: @escaping (CGPoint, CGSize) -> Void,
      onDragEnded: @escaping () -> Void
    ) {
      self.onTap = onTap
      self.onDragBegan = onDragBegan
      self.onDragChanged = onDragChanged
      self.onDragEnded = onDragEnded
    }

    @objc func handleTap() {
      onTap()
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let view = recognizer.view else { return }
      switch recognizer.state {
      case .began:
        isDragging = true
        onDragBegan()
        fallthrough
      case .changed:
        let translation = recognizer.translation(in: view)
        onDragChanged(translation, view.bounds.size)
      case .ended, .cancelled, .failed:
        guard isDragging else { return }
        isDragging = false
        onDragEnded()
      default:
        break
      }
    }
  }
}
