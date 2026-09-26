import SwiftUI
import UniformTypeIdentifiers

struct SegmentEditorView: View {
  let editor: any SegmentEditing
  let player: SegmentPlayer
  var recordTitle = "Record"
  var focusTitle: String?

  @Environment(Toasts.self) private var toasts
  @State private var selectedSegment: String?
  @State private var selectedRange: ClosedRange<Double>?
  @State private var viewport = TimelineViewport()
  @State private var pendingDelete: ClipMeta?
  @State private var pendingRangeDelete: ClosedRange<Double>?
  @State private var isImporting = false

  private var urls: [URL] {
    guard let folder = editor.segmentFolder else { return [] }
    return editor.segments.map { folder.appending(path: $0.name) }
  }

  var body: some View {
    VStack(spacing: 0) {
      timelineBar

      SegmentTimeline(
        segments: editor.segments,
        folder: editor.segmentFolder,
        player: player,
        viewport: viewport,
        selection: $selectedSegment,
        range: $selectedRange,
        canReorder: !editor.isLocked && !editor.isWorking,
        move: move,
        delete: deleteSelected
      ) { clip, index in
        menu(for: clip, index: index)
      }
      .frame(minHeight: 160, maxHeight: .infinity)
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 16)

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
    .onChange(of: editor.segments.map(\.name)) {
      selectedRange = nil
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
    .confirmationDialog("Delete selection?", isPresented: isConfirmingRangeDelete, presenting: pendingRangeDelete) { range in
      Button("Delete Selection", role: .destructive) {
        carve(.delete, range: range)
      }
    } message: { range in
      Text("This removes \(Formatting.preciseDuration(range.upperBound - range.lowerBound)) of audio from this recording.")
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

  private var transport: some View {
    HStack(spacing: 12) {
      if !editor.isLocked {
        Button("Add File", systemImage: "plus") { isImporting = true }
          .buttonStyle(.borderless)
          .labelStyle(.titleAndIcon)
          .disabled(editor.isWorking)
          .help("Add Audio File… (⇧⌘I)")
      }

      TransportBar(player: player, canSplit: canSplit, split: editor.isLocked ? nil : { split() })
    }
  }

  private var timelineBar: some View {
    HStack(spacing: 14) {
      if let selectedRange, !editor.isLocked {
        Text("\(Formatting.preciseDuration(selectedRange.upperBound - selectedRange.lowerBound)) selected")
          .monospacedDigit()
          .foregroundStyle(.secondary)

        Button("Split", systemImage: "scissors") { carve(.split, range: selectedRange) }
          .help("Split at the selection edges (⌘T)")
          .disabled(editor.isWorking)

        Button("Delete", systemImage: "trash") { pendingRangeDelete = selectedRange }
          .help("Delete the selected audio (⌫)")
          .disabled(editor.isWorking)
      } else if !editor.isLocked {
        Text("Drag across the waveform to select audio.")
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 0)

      if editor.isWorking || player.isLoading {
        ProgressView()
          .controlSize(.small)
      }

      zoomSlider
    }
    .buttonStyle(.borderless)
    .font(.callout)
    .frame(minHeight: 24)
    .padding(.horizontal, 20)
    .padding(.top, 10)
  }

  private var zoomSlider: some View {
    HStack(spacing: 6) {
      Image(systemName: "minus.magnifyingglass")
      Slider(
        value: Binding(
          get: { log(viewport.zoom) },
          set: { viewport.setZoom(exp($0), anchor: viewport.screenX(at: player.currentTime)) }
        ),
        in: 0...max(log(viewport.maxZoom), 0.01)
      )
      .controlSize(.mini)
      .frame(width: 90)
      Image(systemName: "plus.magnifyingglass")
    }
    .foregroundStyle(.secondary)
    .disabled(viewport.maxZoom <= 1)
    .help("Zoom (⌘+ / ⌘−)")
  }

  private var segmentActions: SegmentActions {
    SegmentActions(
      togglePlayback: { player.toggle() },
      split: canSplit ? { split() } : nil,
      importAudio: editor.isLocked ? nil : { isImporting = true },
      zoomIn: viewport.zoom < viewport.maxZoom ? { viewport.zoom(by: 1.5, around: player.currentTime) } : nil,
      zoomOut: viewport.zoom > 1 ? { viewport.zoom(by: 1 / 1.5, around: player.currentTime) } : nil,
      zoomToFit: viewport.zoom > 1 ? { viewport.setZoom(1) } : nil
    )
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
  }

  private var isConfirmingRangeDelete: Binding<Bool> {
    Binding(get: { pendingRangeDelete != nil }, set: { if !$0 { pendingRangeDelete = nil } })
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
    guard !editor.isLocked, !editor.isWorking else { return }

    if let selectedRange {
      pendingRangeDelete = selectedRange
    } else if let clip = editor.segments.first(where: { $0.name == selectedSegment }) {
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

      Group {
        if let selectedRange {
          Button("Split at Selection") { carve(.split, range: selectedRange) }
          Button("Delete Selection…", role: .destructive) { pendingRangeDelete = selectedRange }
          Divider()
        } else if canSplit, currentSegment?.name == clip.name {
          Button("Split at Playhead", action: splitAtPlayhead)
        }

        Button("Delete Segment…", role: .destructive) { requestDelete(clip) }
      }
      .disabled(editor.isWorking)
    }
  }

  private var currentSegment: ClipMeta? {
    guard let index = player.currentSegmentIndex, editor.segments.indices.contains(index) else { return nil }
    return editor.segments[index]
  }

  private var canSplit: Bool {
    guard !editor.isLocked, !editor.isWorking else { return false }
    return selectedRange != nil || canSplitAtPlayhead
  }

  private var canSplitAtPlayhead: Bool {
    guard !editor.isLocked, !editor.isWorking, let index = player.currentSegmentIndex,
          editor.segments.indices.contains(index) else {
      return false
    }

    let local = player.currentTime - player.segmentStart(index)
    let end = index + 1 < player.boundaries.count ? player.boundaries[index + 1] : player.duration
    return local > 0.1 && player.currentTime < end - 0.1
  }

  private func split() {
    if let selectedRange {
      carve(.split, range: selectedRange)
    } else {
      splitAtPlayhead()
    }
  }

  private var spans: [SegmentCarving.Span] {
    let segments = editor.segments
    let useBoundaries = player.boundaries.count == segments.count && player.duration > 0
    var start = 0.0

    return segments.indices.map { index in
      let duration: Double
      if useBoundaries {
        let end = index + 1 < player.boundaries.count ? player.boundaries[index + 1] : player.duration
        start = player.boundaries[index]
        duration = max(end - start, 0)
      } else {
        duration = segments[index].durationSeconds
      }

      defer { start += duration }
      return SegmentCarving.Span(name: segments[index].name, start: start, duration: duration)
    }
  }

  private func carve(_ edit: SegmentCarving.Edit, range: ClosedRange<Double>) {
    guard !editor.isLocked, !editor.isWorking else { return }
    let plan = SegmentCarving.plan(edit, range: range, spans: spans)
    guard !plan.isEmpty else { return }

    player.pause()
    run {
      try await editor.carve(keeping: plan)
      selectedRange = nil
    }
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
        .lineLimit(1)
        .fixedSize()

      if let split {
        Button(action: split) {
          Image(systemName: "scissors")
        }
        .disabled(!canSplit)
        .help("Split at Playhead or Selection (⌘T)")
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
  let zoomIn: (() -> Void)?
  let zoomOut: (() -> Void)?
  let zoomToFit: (() -> Void)?
}

extension FocusedValues {
  @Entry var segmentActions: SegmentActions?
}
