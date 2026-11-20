import SwiftUI

struct RecordingCardView: View {
  let title: String?
  let autoStart: Bool
  let onFinish: (RecordedTake) async throws -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    RecordingPanel(style: .card(title: title), autoStart: autoStart) { take in
      try await onFinish(take)
      dismiss()
    } onCancel: {
      dismiss()
    }
    .frame(width: 450, height: 460)
    .interactiveDismissDisabled()
  }
}
