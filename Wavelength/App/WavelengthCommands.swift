import SwiftUI

struct WavelengthCommands: Commands {
  let model: AppModel
  let updates: SoftwareUpdates

  @FocusedValue(\.episodeActions) private var episode
  @FocusedValue(\.segmentActions) private var segment
  @FocusedValue(\.startRecording) private var startRecording
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    let _ = model.openMainWindow = { openWindow(id: WindowID.main) }

    CommandGroup(after: .appInfo) {
      Button("Check for Updates…", action: updates.checkForUpdates)
        .disabled(!updates.canCheckForUpdates || model.recorder.isActive || model.sheet != nil || model.posts.isAttaching)
    }

    CommandGroup(replacing: .newItem) {
      Button("New Episode") { model.startNewEpisode() }
        .keyboardShortcut("n")
        .disabled(!model.session.isSignedIn)
    }

    CommandGroup(replacing: .importExport) {
      Button("Import Audio…") { segment?.importAudio?() }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(segment?.importAudio == nil)

      Button("Export Audio…") { episode?.export() }
        .keyboardShortcut("e")
        .disabled(episode == nil)
    }

    CommandGroup(after: .printItem) {
      Divider()

      Button("Sign Out") { model.confirmSignOut() }
        .disabled(!model.session.isSignedIn)
    }

    CommandMenu("Episode") {
      Button((episode?.isPlaying ?? segment?.isPlaying ?? false) ? "Pause" : "Play") {
        (episode?.togglePlayback ?? segment?.togglePlayback)?()
      }
      .disabled(segment == nil)

      Button("Split") { segment?.split?() }
        .keyboardShortcut("t")
        .disabled(segment?.split == nil)

      Button("Record") { startRecording?.start() }
        .keyboardShortcut("r")
        .disabled(startRecording == nil)

      Divider()

      Button("Post…") { episode?.publish?() }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(episode?.publish == nil)

      Button("Rename") { episode?.rename() }
        .disabled(episode == nil)

      Button("Duplicate") { episode?.duplicate() }
        .keyboardShortcut("d")
        .disabled(episode == nil)
    }

    CommandGroup(before: .sidebar) {
      ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
        Button(item.title) { model.showSection(item) }
          .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
      }

      Divider()

      Button("Zoom In") { segment?.zoomIn?() }
        .keyboardShortcut("+")
        .disabled(segment?.zoomIn == nil)

      Button("Zoom Out") { segment?.zoomOut?() }
        .keyboardShortcut("-")
        .disabled(segment?.zoomOut == nil)

      Button("Zoom to Fit") { segment?.zoomToFit?() }
        .keyboardShortcut("0")
        .disabled(segment?.zoomToFit == nil)

      Divider()

      ForEach(PostsStore.Filter.allCases) { filter in
        Toggle(filter.label, isOn: Binding(
          get: { model.posts.filter == filter },
          set: { _ in model.posts.filter = filter }
        ))
        .disabled(model.sidebar != .posts)
      }

      Divider()
    }
  }
}
