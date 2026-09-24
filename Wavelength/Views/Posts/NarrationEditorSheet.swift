import SwiftUI

struct NarrationEditorSheet: View {
  let postUID: String
  let source: URL

  @Environment(AppModel.self) private var model
  @Environment(NarrationDraft.self) private var draft
  @Environment(Recorder.self) private var recorder
  @Environment(Toasts.self) private var toasts
  @Environment(\.dismiss) private var dismiss
  @State private var player = SegmentPlayer()
  @State private var isSaving = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Edit Narration")
            .font(.title2.weight(.bold))
          Text("Split, reorder, and add segments. Your changes replace the current take.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(20)

      Divider()

      Group {
        if draft.isOpen(for: postUID) {
          SegmentEditorView(editor: draft, player: player)
        } else {
          VStack(spacing: 12) {
            ProgressView()
            Text("Preparing audio…")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }

      Divider()

      HStack {
        if draft.isOpen(for: postUID) {
          Text("\(Formatting.duration(draft.durationSeconds)) · \(Formatting.fileSize(draft.totalSizeBytes))")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button("Cancel", role: .cancel) {
          recorder.cancel()
          player.reset()
          draft.discard()
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(isSaving ? "Preparing…" : "Use This Audio") { commit() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!draft.isOpen(for: postUID) || isSaving || draft.isWorking || recorder.isActive)
      }
      .padding(16)
    }
    .frame(width: 820, height: 680)
    .interactiveDismissDisabled()
    .task {
      do {
        try await draft.open(postUID: postUID, audio: source)
      } catch {
        toasts.show(error.localizedDescription)
        dismiss()
      }
    }
  }

  private func commit() {
    isSaving = true
    player.reset()

    Task {
      do {
        model.pendingNarrationTakes[postUID] = try await draft.commit()
        dismiss()
      } catch {
        toasts.show(error.localizedDescription)
      }

      isSaving = false
    }
  }
}
