import SwiftUI

struct EpisodeAttachmentCard: View {
  let episode: Episode
  let isPublishing: Bool

  @State private var player = SegmentPlayer()

  private var urls: [URL] {
    episode.clips.map(episode.url(for:))
  }

  private var duration: Double {
    player.duration > 0 ? player.duration : episode.durationSeconds
  }

  private var gain: Float {
    let peak = episode.waveform.max() ?? 0
    return peak > 0 ? min(0.9 / peak, 6) : 1
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Label {
            Text("Attached Episode")
              .foregroundStyle(Color.inkSoft)
          } icon: {
            Image(systemName: "waveform")
              .foregroundStyle(Color.accentColor)
          }
          .font(.caption.weight(.bold))
          .textCase(.uppercase)

          Text(episode.title)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer(minLength: 0)

        Text("\(Formatting.duration(player.currentTime)) / \(Formatting.duration(duration)) · \(Formatting.fileSize(episode.totalSizeBytes))")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(Color.inkSoft)
          .fixedSize()
      }

      if episode.isOverUploadLimit {
        Text(Formatting.uploadLimitMessage(episode.totalSizeBytes))
          .font(.callout.weight(.semibold))
          .foregroundStyle(Color.accentColor)
      }

      HStack(spacing: 10) {
        Button {
          player.toggle()
        } label: {
          PlayPauseCircle(isPlaying: player.isPlaying, size: 36)
        }
        .buttonStyle(.plain)
        .disabled(player.duration <= 0 || isPublishing)
        .help(player.isPlaying ? "Pause" : "Play")

        WaveformView(levels: episode.waveform, progress: player.progress, gain: gain)
          .frame(height: 36)
          .overlay {
            GeometryReader { geometry in
              Color.clear
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                  player.seek(fraction: min(max(value.location.x / max(geometry.size.width, 1), 0), 1))
                })
            }
          }
          .accessibilityElement()
          .accessibilityLabel("Playback position")
          .accessibilityValue("\(Formatting.duration(player.currentTime)) of \(Formatting.duration(duration))")
          .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.skip(by: 5)
            case .decrement: player.skip(by: -5)
            @unknown default: break
            }
          }
      }
    }
    .padding(12)
    .background(Color.paper, in: .rect(cornerRadius: 14))
    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line) }
    .task(id: urls) {
      await player.load(urls)
    }
    .onChange(of: isPublishing) { _, isPublishing in
      if isPublishing {
        player.pause()
      }
    }
    .onDisappear {
      player.reset()
    }
  }
}
