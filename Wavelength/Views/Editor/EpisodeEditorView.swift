import SwiftUI

struct EpisodeEditorView: View {
  let episodeID: String

  @Environment(AppModel.self) private var model
  @Environment(Library.self) private var library
  @Environment(Toasts.self) private var toasts
  @Environment(\.openURL) private var openURL
  @State private var document: EpisodeDocument?
  @State private var player = SegmentPlayer()
  @State private var titleDraft = ""
  @State private var isRenaming = false
  @State private var isConfirmingDelete = false
  @State private var isExporting = false
  @FocusState private var isTitleFocused: Bool

  var body: some View {
    Group {
      if let episode = library.episode(episodeID), let document {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            header(episode)
            SegmentEditorView(editor: document, player: player)
          }
          .padding(24)
          .frame(maxWidth: 980)
          .frame(maxWidth: .infinity)
        }
        .background(Color.canvas)
        .toolbar { toolbar(episode) }
        .focusedSceneValue(\.episodeActions, actions(for: episode))
        .onKeyPress(.space) {
          player.toggle()
          return .handled
        }
        .episodeDeleteDialog(episode: episode, isPresented: $isConfirmingDelete)
      } else {
        EmptyStateView(symbol: "waveform", title: "Episode Unavailable", message: "This episode is no longer available.")
      }
    }
    .navigationTitle(library.episode(episodeID)?.title ?? "Episode")
    .onAppear {
      document = EpisodeDocument(id: episodeID, library: library)
    }
    .onDisappear {
      player.reset()
    }
  }

  private func header(_ episode: Episode) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if isRenaming {
        TextField("Episode name", text: $titleDraft)
          .textFieldStyle(.plain)
          .font(.largeTitle.weight(.bold))
          .focused($isTitleFocused)
          .onSubmit(commitRename)
          .onExitCommand { isRenaming = false }
          .onChange(of: isTitleFocused) { _, focused in
            if !focused { commitRename() }
          }
      } else {
        Text(episode.title)
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(Color.ink)
          .onTapGesture(count: 2, perform: startRename)
          .help("Double-click to rename")
      }

      HStack(spacing: 10) {
        Text(metadata(episode))
          .foregroundStyle(Color.inkSoft)

        if episode.isPublished {
          Button {
            if let url = episode.postURL.flatMap(URL.init(string:)) { openURL(url) }
          } label: {
            Label("Published", systemImage: "checkmark.seal.fill")
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)
          .help("View the post on Micro.blog")
        }
      }
      .font(.callout)

      if episode.isOverUploadLimit {
        Label(Formatting.uploadLimitMessage(episode.totalSizeBytes), systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(Color.orange)
      }
    }
  }

  @ToolbarContentBuilder
  private func toolbar(_ episode: Episode) -> some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      if episode.isPublished {
        if let uid = episode.postID {
          Button {
            model.sheet = .editPost(postUID: uid)
          } label: {
            Label("Edit Post", systemImage: "square.and.pencil")
          }
        }
      } else {
        Button {
          model.sheet = .publish(episodeID: episode.id)
        } label: {
          Label("Publish", systemImage: "paperplane.fill")
        }
        .buttonStyle(.borderedProminent)
        .help("Publish to Micro.blog (⇧⌘P)")
      }

      Menu {
        EpisodeMenuItems(episode: episode, rename: startRename, export: export, delete: { isConfirmingDelete = true })
      } label: {
        Label("More", systemImage: "ellipsis")
      }
    }
  }

  private func metadata(_ episode: Episode) -> String {
    var parts: [String] = []

    if let date = episode.publishedAt ?? episode.createdAt {
      parts.append(date.formatted(date: .abbreviated, time: .shortened))
    }

    parts.append(Formatting.duration(episode.durationSeconds))
    parts.append(episode.clips.count == 1 ? "1 segment" : "\(episode.clips.count) segments")
    parts.append(Formatting.fileSize(episode.totalSizeBytes))
    return parts.joined(separator: " · ")
  }

  private func actions(for episode: Episode) -> EpisodeActions {
    EpisodeActions(
      publish: episode.isPublished ? nil : { model.sheet = .publish(episodeID: episode.id) },
      rename: startRename,
      duplicate: { model.duplicate(episode: episode.id) },
      export: export,
      delete: { isConfirmingDelete = true }
    )
  }

  private func startRename() {
    guard let episode = library.episode(episodeID) else { return }
    titleDraft = episode.title
    isRenaming = true
    isTitleFocused = true
  }

  private func commitRename() {
    guard isRenaming else { return }
    isRenaming = false

    do {
      try library.rename(episodeID, to: titleDraft)
    } catch {
      toasts.show(error.localizedDescription)
    }
  }

  private func export() {
    guard !isExporting, let episode = library.episode(episodeID) else { return }
    isExporting = true

    Task {
      defer { isExporting = false }

      do {
        let merged = try await library.mergedAudio(episode.id)
        await AudioExporter.save(merged, suggestedName: Formatting.exportFilename(for: episode.title))
      } catch {
        toasts.show(error.localizedDescription)
      }
    }
  }
}

struct EpisodeMenuItems: View {
  let episode: Episode
  var listen: (() -> Void)?
  let rename: () -> Void
  let export: () -> Void
  let delete: () -> Void

  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL

  var body: some View {
    if let listen {
      Button("Listen", systemImage: "play.fill", action: listen)
    }

    if episode.isPublished {
      if let url = episode.postURL.flatMap(URL.init(string:)) {
        Button("View Post", systemImage: "safari") { openURL(url) }
      }

      if let uid = episode.postID {
        Button("Edit Post…", systemImage: "square.and.pencil") { model.sheet = .editPost(postUID: uid) }
      }
    } else {
      Button("Publish…", systemImage: "paperplane") { model.sheet = .publish(episodeID: episode.id) }
    }

    Divider()
    Button("Rename", systemImage: "pencil", action: rename)
    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(episode: episode.id) }
    Button("Export Audio…", systemImage: "square.and.arrow.up", action: export)
    Button("Show in Finder", systemImage: "folder") {
      NSWorkspace.shared.activateFileViewerSelecting([episode.folder])
    }
    Divider()
    Button("Delete Episode…", systemImage: "trash", role: .destructive, action: delete)
  }
}

struct EpisodeActions {
  let publish: (() -> Void)?
  let rename: () -> Void
  let duplicate: () -> Void
  let export: () -> Void
  let delete: () -> Void
}

extension FocusedValues {
  @Entry var episodeActions: EpisodeActions?
}

extension View {
  func episodeDeleteDialog(episode: Episode, isPresented: Binding<Bool>) -> some View {
    modifier(EpisodeDeleteDialog(episode: episode, isPresented: isPresented))
  }
}

private struct EpisodeDeleteDialog: ViewModifier {
  let episode: Episode
  @Binding var isPresented: Bool
  @Environment(AppModel.self) private var model

  func body(content: Content) -> some View {
    content.confirmationDialog("Delete “\(episode.title)”?", isPresented: $isPresented) {
      if episode.isPublished {
        Button("Remove from This Mac", role: .destructive) {
          Task { await model.delete(episode: episode.id, deletingPost: false) }
        }
        Button("Delete Everywhere", role: .destructive) {
          Task { await model.delete(episode: episode.id, deletingPost: true) }
        }
      } else {
        Button("Delete", role: .destructive) {
          Task { await model.delete(episode: episode.id, deletingPost: false) }
        }
      }
    } message: {
      if episode.isPublished {
        Text("You can remove it from this Mac and keep its Micro.blog post, or delete it everywhere.")
      } else {
        Text("It will be permanently removed from this Mac.")
      }
    }
  }
}

enum AudioExporter {
  static func save(_ source: URL, suggestedName: String) async {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.mpeg4Audio]
    panel.nameFieldStringValue = suggestedName
    panel.canCreateDirectories = true

    guard await panel.begin() == .OK, let destination = panel.url else { return }

    try? FileManager.default.removeItem(at: destination)
    try? FileManager.default.copyItem(at: source, to: destination)
  }
}
