import SwiftUI

struct RecordingCardView: View {
  let title: String
  let autoStart: Bool
  let onFinish: (RecordedTake) async throws -> Void

  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShown = false

  var body: some View {
    RecordingPanel(style: .card(title: title), autoStart: autoStart) { take in
      try await onFinish(take)
      dismiss()
    } onCancel: {
      dismiss()
    }
    .floatingCard(width: 400, height: 500)
    .scaleEffect(isShown || reduceMotion ? 1 : 0.94)
    .offset(y: isShown || reduceMotion ? 0 : 14)
    .opacity(isShown ? 1 : 0)
    .onAppear {
      Task {
        withAnimation(.spring(duration: 0.5, bounce: 0.22)) {
          isShown = true
        }
      }
    }
  }

  private func dismiss() {
    withAnimation(.easeIn(duration: 0.2)) {
      isShown = false
    }

    Task {
      try? await Task.sleep(for: .seconds(0.2))
      model.endRecordingFocus()
    }
  }
}
