import SwiftUI
import UniformTypeIdentifiers

struct SegmentEditorView: View {
  let editor: any SegmentEditing
  let player: SegmentPlayer
  var recordTitle = "Record"
  var focusTitle: String?

  @Environment(Toasts.self) private var toasts
  @State private var selectedSegment: String?
  @State private var pendingDelete: ClipMeta?
  @State private var isImporting = false

  private var urls: [URL] {
    guard let folder = editor.segmentFolder else { return [] }
    return editor.segments.map { folder.appending(path: $0.name) }
  }

  var body: some View {
    VStack(spacing: 0) {
      SegmentTimeline(
        segments: editor.segments,
        folder: editor.segmentFolder,
        player: player,
        selection: $selectedSegment,
        canReorder: !editor.isLocked && !editor.isWorking,
        move: move,
        delete: deleteSelected
      ) { clip, index in
        menu(for: clip, index: index)
      }
      .frame(minHeight: 160, maxHeight: .infinity)
      .padding(.horizontal, 20)
      .padding(.top, 14)
      .padding(.bottom, 16)
      .overlay(alignment: .topTrailing) {
        if editor.isWorking || player.isLoading {
          ProgressView()
            .controlSize(.small)
            .padding(.trailing, 20)
            .padding(.top, 14)
        }
      }

      if editor.isLocked {
        Label("This episode is published, so its audio is locked. Duplicate it to make changes.", systemImage: "lock")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 20)
          .padding(.bottom, 12)
      }

      Divider()

      controlBar
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    .task(id: urls) {
      await player.load(urls)
    }
    .focusedSceneValue(\.segmentActions, segmentActions)
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
      if case .success(let url) = result {
        importAudio(url)
      }
    }
    .dropDestination(for: URL.self, action: dropAudio)
    .confirmationDialog("Delete segment?", isPresented: isConfirmingDelete, presenting: pendingDelete) { clip in
      Button("Delete Segment", role: .destructive) {
        run { try await editor.deleteSegment(clip) }
      }
    } message: { _ in
      Text("This removes the segment from this recording.")
    }
  }

  @ViewBuilder
  private var controlBar: some View {
    if editor.isLocked {
      transport
    } else {
      RecordingPanel(idleTitle: recordTitle, style: .bar, focusTitle: focusTitle, onFinish: appendRecording) {
        transport
      }
    }
  }

  @ViewBuilder
  private var transport: some View {
    if editor.isLocked {
      TransportBar(player: player)
    } else {
      HStack(spacing: 12) {
        Button("Add File", systemImage: "plus") { isImporting = true }
          .buttonStyle(.borderless)
          .labelStyle(.titleAndIcon)
          .disabled(editor.isWorking)
          .help("Add Audio File… (⇧⌘I)")

        TransportBar(player: player, canSplit: canSplit, split: splitAtPlayhead)
      }
    }
  }

  private var segmentActions: SegmentActions {
    let importAction: (() -> Void)? = editor.isLocked ? nil : { isImporting = true }
    let splitAction: (() -> Void)? = canSplit ? { splitAtPlayhead() } : nil
    return SegmentActions(togglePlayback: { player.toggle() }, split: splitAction, importAudio: importAction)
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
  }

  private func appendRecording(_ take: RecordedTake) async throws {
    try await editor.appendRecording(take)
    player.seek(to: player.duration)
  }

  private func dropAudio(_ urls: [URL], _ location: CGPoint) -> Bool {
    guard !editor.isLocked else { return false }
    let files = urls.filter(\.isFileURL)
    files.forEach(importAudio)
    return !files.isEmpty
  }

  private func deleteSelected() {
    if let clip = editor.segments.first(where: { $0.name == selectedSegment }) {
      requestDelete(clip)
    }
  }

  @ViewBuilder
  private func menu(for clip: ClipMeta, index: Int) -> some View {
    Button("Play from Here") { player.play(segment: index) }

    if let folder = editor.segmentFolder {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([folder.appending(path: clip.name)])
      }
    }

    if !editor.isLocked {
      Divider()

      if canSplit, currentSegment?.name == clip.name {
        Button("Split at Playhead", action: splitAtPlayhead)
      }

      Button("Delete Segment…", role: .destructive) { requestDelete(clip) }
    }
  }

  private var currentSegment: ClipMeta? {
    guard let index = player.currentSegmentIndex, editor.segments.indices.contains(index) else { return nil }
    return editor.segments[index]
  }

  private var canSplit: Bool {
    guard !editor.isLocked, !editor.isWorking, let index = player.currentSegmentIndex,
          editor.segments.indices.contains(index) else {
      return false
    }

    let local = player.currentTime - player.segmentStart(index)
    let end = index + 1 < player.boundaries.count ? player.boundaries[index + 1] : player.duration
    return local > 0.1 && player.currentTime < end - 0.1
  }

  private func splitAtPlayhead() {
    guard let index = player.currentSegmentIndex, editor.segments.indices.contains(index) else { return }

    let clip = editor.segments[index]
    let local = player.currentTime - player.segmentStart(index)
    player.pause()
    run { try await editor.split(clip, at: local) }
  }

  private func requestDelete(_ clip: ClipMeta) {
    guard !editor.isLocked else { return }

    if editor.segments.count <= 1 {
      toasts.show("A recording needs at least one segment.")
    } else {
      pendingDelete = clip
    }
  }

  private func move(from index: Int, to target: Int) {
    var clips = editor.segments
    guard clips.indices.contains(index), clips.indices.contains(target) else { return }
    clips.insert(clips.remove(at: index), at: target)
    run { try await editor.reorder(clips) }
  }

  private func importAudio(_ url: URL) {
    run { try await editor.importAudio(from: url) }
  }

  private func run(_ operation: @escaping () async throws -> Void) {
    Task {
      do {
        try await operation()
      } catch {
        toasts.show(error.localizedDescription)
      }
    }
  }
}

struct TransportBar: View {
  let player: SegmentPlayer
  var canSplit = false
  var split: (() -> Void)?

  var body: some View {
    HStack(spacing: 16) {
      Spacer(minLength: 0)

      Button {
        player.skip(by: -15)
      } label: {
        Image(systemName: "gobackward.15")
      }
      .help("Back 15 seconds")

      Button {
        player.toggle()
      } label: {
        PlayPauseIcon(isPlaying: player.isPlaying, size: 17)
          .frame(width: 24, height: 24)
          .contentShape(.rect)
      }
      .disabled(player.duration <= 0)
      .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")

      Button {
        player.skip(by: 15)
      } label: {
        Image(systemName: "goforward.15")
      }
      .help("Forward 15 seconds")

      Spacer(minLength: 0)

      Text("\(Formatting.preciseDuration(player.currentTime)) / \(Formatting.duration(player.duration))")
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)

      if let split {
        Button(action: split) {
          Image(systemName: "scissors")
        }
        .disabled(!canSplit)
        .help("Split at Playhead (⌘T)")
      }
    }
    .buttonStyle(.borderless)
    .font(.title3)
  }
}

struct SegmentActions {
  let togglePlayback: () -> Void
  let split: (() -> Void)?
  let importAudio: (() -> Void)?
}

extension FocusedValues {
  @Entry var segmentActions: SegmentActions?
}
