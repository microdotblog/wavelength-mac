import SwiftUI

struct EpisodeListView: View {
  @Environment(AppModel.self) private var model
  @Environment(Library.self) private var library
  @Environment(Toasts.self) private var toasts
  @State private var pendingDelete: Episode?
  @State private var renaming: Episode?
  @State private var renameDraft = ""

  var body: some View {
    @Bindable var model = model

    Group {
      if library.episodes.isEmpty, library.didHydrate {
        EmptyStateView(
          symbol: "mic.circle",
          title: "Record your first podcast",
          message: "Start recording, then edit it and publish it to Micro.blog.",
          actionTitle: "New Episode",
          action: model.startNewEpisode
        )
      } else {
        List(selection: $model.selectedEpisodeID) {
          ForEach(library.sortedEpisodes) { episode in
            EpisodeRow(episode: episode)
              .tag(episode.id)
              .contextMenu {
                EpisodeMenuItems(
                  episode: episode,
                  listen: { model.select(episode: episode.id) },
                  rename: { startRename(episode) },
                  export: { export(episode) },
                  delete: { pendingDelete = episode }
                )
              }
          }
        }
        .environment(\.defaultMinListRowHeight, EpisodeRow.height)
        .onDeleteCommand {
          pendingDelete = library.episode(model.selectedEpisodeID)
        }
      }
    }
    .navigationTitle("Podcasts")
    .toolbar {
      ToolbarItem {
        Button(action: model.startNewEpisode) {
          Label("New Episode", systemImage: "plus")
        }
        .help("New Episode (⌘N)")
      }
    }
    .onChange(of: model.selectedEpisodeID) { _, id in
      if id != nil {
        model.isRecordingNewEpisode = false
      }
    }
    .alert("Rename Episode", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField("Episode name", text: $renameDraft)
      Button("Rename") { commitRename() }
      Button("Cancel", role: .cancel) {}
    }
    .modifier(OptionalEpisodeDeleteDialog(episode: $pendingDelete))
  }

  private func startRename(_ episode: Episode) {
    renameDraft = episode.title
    renaming = episode
  }

  private func commitRename() {
    guard let renaming else { return }

    do {
      try library.rename(renaming.id, to: renameDraft)
    } catch {
      toasts.show(error.localizedDescription)
    }
  }

  private func export(_ episode: Episode) {
    Task {
      do {
        let merged = try await library.mergedAudio(episode.id)
        await AudioExporter.save(merged, suggestedName: Formatting.exportFilename(for: episode.title))
      } catch {
        toasts.show(error.localizedDescription)
      }
    }
  }
}

private struct OptionalEpisodeDeleteDialog: ViewModifier {
  @Binding var episode: Episode?

  func body(content: Content) -> some View {
    if let current = episode {
      content.episodeDeleteDialog(
        episode: current,
        isPresented: Binding(get: { episode != nil }, set: { if !$0 { episode = nil } })
      )
    } else {
      content
    }
  }
}

struct EpisodeRow: View {
  static let height: CGFloat = 60

  let episode: Episode
  @Environment(Library.self) private var library

  var body: some View {
    HStack(spacing: 12) {
      WaveformView(levels: episode.waveform, barWidth: 2, spacing: 1)
        .frame(width: 56, height: 32)
        .padding(6)
        .background(Color.paperAlt, in: .rect(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(episode.title)
            .font(.body.weight(.semibold))
            .lineLimit(1)

          if episode.isPublished {
            Image(systemName: "checkmark.seal.fill")
              .foregroundStyle(Color.accentColor)
              .help("Published")
          }
        }

        Text(subtitle)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      if library.isWorking(episode.id) {
        ProgressView().controlSize(.small)
      }
    }
    .frame(height: Self.height - 8)
  }

  private var subtitle: String {
    let date = (episode.publishedAt ?? episode.createdAt)?.formatted(date: .abbreviated, time: .omitted) ?? ""
    let segments = episode.clips.count == 1 ? "1 segment" : "\(episode.clips.count) segments"
    return [date, Formatting.duration(episode.durationSeconds), segments].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
