import SwiftUI

struct NewRecordingView: View {
  @Environment(AppModel.self) private var model
  @Environment(Recorder.self) private var recorder
  @State private var isConfirmingCancel = false

  var body: some View {
    VStack(spacing: 12) {
      Spacer()

      Text("New Episode")
        .font(.title.weight(.bold))
        .foregroundStyle(Color.ink)

      Text("Record the first segment. You can add more, split, and reorder them afterwards.")
        .foregroundStyle(Color.inkSoft)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .padding(.bottom, 24)

      RecordingPanel(style: .hero) { take in
        model.finishNewEpisode(take)
      } onCancel: {
        model.isRecordingNewEpisode = false
      }

      Spacer()
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.canvas)
    .navigationTitle("New Episode")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          if recorder.isActive {
            isConfirmingCancel = true
          } else {
            model.isRecordingNewEpisode = false
          }
        }
      }
    }
    .confirmationDialog("Discard this recording?", isPresented: $isConfirmingCancel) {
      Button("Discard Recording", role: .destructive) {
        recorder.cancel()
        model.isRecordingNewEpisode = false
      }
      Button("Keep Recording", role: .cancel) {}
    } message: {
      Text("This removes the current take without saving it.")
    }
  }
}
