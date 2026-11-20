import SwiftUI

struct WavelengthCommands: Commands {
  let model: AppModel

  @FocusedValue(\.episodeActions) private var episode
  @FocusedValue(\.segmentActions) private var segment
  @FocusedValue(\.startRecording) private var startRecording
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    @Bindable var posts = model.posts
    let _ = model.openMainWindow = { openWindow(id: WindowID.main) }

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

    CommandGroup(before: .toolbar) {
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
    }

    CommandGroup(before: .sidebar) {
      ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
        Button(item.title) { model.showSection(item) }
          .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
          .disabled(item == .narrations && model.posts.narratedPosts.isEmpty)
      }

      Divider()

      Picker("Filter Posts", selection: $posts.filter) {
        ForEach(PostsStore.Filter.allCases) { filter in
          Text(filter.label).tag(filter)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
      .disabled(model.sidebar != .posts)

      Divider()
    }
  }
}
