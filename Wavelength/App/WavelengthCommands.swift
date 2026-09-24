import SwiftUI

struct WavelengthCommands: Commands {
  let model: AppModel

  @FocusedValue(\.episodeActions) private var episode
  @FocusedValue(\.segmentActions) private var segment
  @FocusedValue(\.recordingActions) private var recording
  @FocusedValue(\.startRecording) private var startRecording
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    let _ = model.openMainWindow = { openWindow(id: WindowID.main) }

    CommandGroup(replacing: .newItem) {
      Button("New Episode") { model.startNewEpisode() }
        .keyboardShortcut("n")
        .disabled(!model.session.isSignedIn)

      Button("Add Audio File…") { segment?.importAudio?() }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(segment?.importAudio == nil)
    }

    CommandGroup(replacing: .saveItem) {
      Button("Export Audio…") { episode?.export() }
        .keyboardShortcut("e")
        .disabled(episode == nil)
    }

    CommandMenu("Episode") {
      Button("Play/Pause") { segment?.togglePlayback() }
        .disabled(segment == nil)

      Button("Split at Playhead") { segment?.split?() }
        .keyboardShortcut("t")
        .disabled(segment?.split == nil)

      Divider()

      Button("Record") { startRecording?.start() }
        .keyboardShortcut("r")
        .disabled(startRecording == nil)

      Button("Pause/Resume Recording") { recording?.togglePause() }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(recording == nil)

      Button("Finish Recording") { recording?.finish() }
        .disabled(recording == nil)

      Divider()

      Button("Publish…") { episode?.publish?() }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(episode?.publish == nil)

      Button("Rename") { episode?.rename() }
        .disabled(episode == nil)

      Button("Duplicate") { episode?.duplicate() }
        .keyboardShortcut("d")
        .disabled(episode == nil)

      Divider()

      Button("Delete Episode…") { episode?.delete() }
        .disabled(episode == nil)
    }

    CommandGroup(before: .sidebar) {
      ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
        Button(item.title) { model.sidebar = item }
          .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
      }

      Divider()
    }
  }
}
