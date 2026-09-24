import SwiftUI

struct NarrateView: View {
  let postUID: String

  @Environment(AppModel.self) private var model
  @Environment(PostsStore.self) private var posts
  @Environment(Recorder.self) private var recorder
  @Environment(Toasts.self) private var toasts
  @Environment(\.openURL) private var openURL
  @State private var player = SegmentPlayer()
  @State private var take: RecordedTake?
  @State private var isConfirmingRemove = false
  @State private var isConfirmingDiscard = false
  @State private var isConfirmingDelete = false
  @AppStorage("teleprompterFontSize") private var fontSize = 20

  private var post: Post? { posts.post(postUID) }
  private var remoteURL: URL? { post.flatMap { URL(string: $0.narrationAudioURL) } }
  private var playbackURL: URL? { take?.url ?? (recorder.isActive ? nil : remoteURL) }

  var body: some View {
    if let post {
      VStack(spacing: 0) {
        Teleprompter(title: post.title, content: post.content, fontSize: fontSize)
        Divider()
        bar
          .padding(14)
          .background(.bar)
      }
      .navigationTitle(post.displayTitle)
      .toolbar { toolbar(post) }
      .task(id: playbackURL) {
        await player.load(playbackURL.map { [$0] } ?? [])
      }
      .onChange(of: model.pendingNarrationTakes[postUID], initial: true) { _, pending in
        guard let pending else { return }
        model.pendingNarrationTakes[postUID] = nil
        replaceTake(with: pending)
      }
      .onKeyPress(.space) {
        guard !recorder.isActive, playbackURL != nil else { return .ignored }
        player.toggle()
        return .handled
      }
      .onDisappear {
        player.reset()

        if let take {
          model.pendingNarrationTakes[postUID] = take
        }
      }
      .confirmationDialog("Delete narration?", isPresented: $isConfirmingRemove) {
        Button("Delete Narration", role: .destructive) {
          Task { await model.removeNarration(from: postUID) }
        }
      } message: {
        Text("This removes the audio from the post. The post itself stays.")
      }
      .confirmationDialog("Discard this take?", isPresented: $isConfirmingDiscard) {
        Button("Discard Take", role: .destructive) { replaceTake(with: nil) }
      } message: {
        Text("The recording hasn’t been saved to your post yet.")
      }
      .confirmationDialog("Delete this post?", isPresented: $isConfirmingDelete) {
        Button("Delete Post", role: .destructive) {
          Task { await model.delete(post: postUID) }
        }
      } message: {
        Text("This deletes the post from Micro.blog.")
      }
    } else {
      EmptyStateView(symbol: "text.bubble", title: "Post Unavailable", message: "This post is no longer available.")
    }
  }

  @ViewBuilder
  private var bar: some View {
    if posts.isAttaching {
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text(posts.attachPhase == .removing ? "Removing narration…" : "Saving narration…")
          .foregroundStyle(.secondary)
        Spacer()
      }
      .frame(height: 44)
    } else if let take {
      review(take)
    } else {
      VStack(spacing: 10) {
        if remoteURL != nil, !recorder.isActive {
          playbackRow(waveform: [])
        }

        RecordingPanel(idleTitle: remoteURL == nil ? "Record Narration" : "Re-record Narration") { newTake in
          model.pendingNarrationTakes[postUID] = newTake
        }
      }
    }
  }

  private func review(_ take: RecordedTake) -> some View {
    VStack(spacing: 10) {
      playbackRow(waveform: take.waveform)

      HStack {
        Label("New take — not saved yet", systemImage: "circle.dotted")
          .font(.callout)
          .foregroundStyle(.secondary)

        Spacer()

        Button("Discard…") { isConfirmingDiscard = true }
        Button("Edit Audio…") { editAudio() }
        RecordingPanelButton(title: "Re-record") { newTake in
          model.pendingNarrationTakes[postUID] = newTake
        }
        Button("Save Narration") { save(take) }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut("s", modifiers: .command)
      }
    }
  }

  private func playbackRow(waveform: [Float]) -> some View {
    HStack(spacing: 12) {
      Button {
        player.toggle()
      } label: {
        PlayPauseCircle(isPlaying: player.isPlaying, size: 30)
      }
      .buttonStyle(.plain)
      .disabled(player.duration <= 0)

      Group {
        if waveform.isEmpty {
          ScrubBar(progress: player.progress) { player.seek(fraction: $0) }
        } else {
          WaveformView(levels: waveform, progress: player.progress)
            .overlay {
              GeometryReader { geometry in
                Color.clear
                  .contentShape(.rect)
                  .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    player.seek(fraction: value.location.x / max(geometry.size.width, 1))
                  })
              }
            }
        }
      }
      .frame(height: 30)

      Text("\(Formatting.duration(player.currentTime)) / \(Formatting.duration(player.duration))")
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }

  @ToolbarContentBuilder
  private func toolbar(_ post: Post) -> some ToolbarContent {
    ToolbarSpacer(.flexible)

    ToolbarItemGroup {
      ControlGroup {
        Button {
          fontSize = max(14, fontSize - 2)
        } label: {
          Label("Smaller Text", systemImage: "textformat.size.smaller")
        }
        Button {
          fontSize = min(40, fontSize + 2)
        } label: {
          Label("Larger Text", systemImage: "textformat.size.larger")
        }
      }
      .help("Teleprompter text size")

      Button {
        model.sheet = .editPost(postUID: post.uid)
      } label: {
        Label("Edit Post", systemImage: "square.and.pencil")
      }

      Menu {
        if let url = URL(string: post.url) {
          Button("Open in Browser", systemImage: "safari") { openURL(url) }
        }

        if remoteURL != nil || take != nil {
          Button("Edit Narration Audio…", systemImage: "waveform") { editAudio() }
            .disabled(recorder.isActive)
        }

        if remoteURL != nil {
          Button("Delete Narration…", systemImage: "trash", role: .destructive) { isConfirmingRemove = true }
            .disabled(recorder.isActive || posts.isAttaching)
        }

        Divider()
        Button("Delete Post…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
      } label: {
        Label("More", systemImage: "ellipsis")
      }
    }
  }

  private func replaceTake(with newTake: RecordedTake?) {
    if let take, take.url != newTake?.url {
      try? FileManager.default.removeItem(at: take.url)
    }

    take = newTake
  }

  private func editAudio() {
    guard let source = take?.url ?? remoteURL else { return }
    player.pause()
    model.sheet = .editNarration(postUID: postUID, source: source)
  }

  private func save(_ take: RecordedTake) {
    player.pause()

    Task {
      do {
        try await posts.attachNarration(to: postUID, audio: take.url)
        replaceTake(with: nil)
        toasts.show("Narration saved.")
      } catch {
        toasts.show(error.localizedDescription)
      }
    }
  }
}

private struct RecordingPanelButton: View {
  let title: String
  let onFinish: (RecordedTake) -> Void

  @State private var isRecording = false

  var body: some View {
    Button(title) { isRecording = true }
      .popover(isPresented: $isRecording) {
        RecordingPanel(idleTitle: "Record", autoStart: true) { take in
          isRecording = false
          onFinish(take)
        } onCancel: {
          isRecording = false
        }
        .frame(width: 520)
        .padding()
      }
  }
}

struct ScrubBar: View {
  let progress: Double
  let seek: (Double) -> Void

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.secondary.opacity(0.25))
        Capsule().fill(Color.accentColor)
          .frame(width: max(4, geometry.size.width * progress))
      }
      .frame(height: 5)
      .frame(maxHeight: .infinity)
      .contentShape(.rect)
      .gesture(DragGesture(minimumDistance: 0).onChanged { value in
        seek(min(max(value.location.x / max(geometry.size.width, 1), 0), 1))
      })
    }
    .accessibilityElement()
    .accessibilityLabel("Playback position")
    .accessibilityValue("\(Int(progress * 100)) percent")
  }
}
