import SwiftUI

struct SegmentTimeline: View {
  let segments: [ClipMeta]
  let folder: URL?
  let player: SegmentPlayer
  var selectedSegment: String?
  var height: CGFloat = 120

  @State private var hoverLocation: CGFloat?
  private let gap: CGFloat = 3

  var body: some View {
    GeometryReader { geometry in
      let layout = TimelineLayout(segments: segments, player: player, width: geometry.size.width, gap: gap)

      ZStack(alignment: .topLeading) {
        ForEach(Array(segments.enumerated()), id: \.element.id) { index, clip in
          let frame = layout.frame(of: index)
          segmentBlock(clip, index: index, layout: layout)
            .frame(width: max(frame.width, 1), height: geometry.size.height)
            .offset(x: frame.minX)
        }

        if let hoverLocation {
          Rectangle()
            .fill(Color.inkSoft.opacity(0.35))
            .frame(width: 1, height: geometry.size.height)
            .offset(x: hoverLocation)

          Text(Formatting.preciseDuration(layout.time(at: hoverLocation)))
            .font(.caption2.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: .capsule)
            .offset(x: min(max(hoverLocation - 24, 0), geometry.size.width - 56), y: -4)
        }

        Playhead(height: geometry.size.height)
          .offset(x: layout.x(at: player.currentTime) - 6)
          .allowsHitTesting(false)
      }
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            player.seek(to: layout.time(at: value.location.x))
          }
      )
      .onContinuousHover { phase in
        switch phase {
        case .active(let location): hoverLocation = min(max(location.x, 0), geometry.size.width)
        case .ended: hoverLocation = nil
        }
      }
    }
    .frame(height: height)
    .accessibilityElement()
    .accessibilityLabel("Timeline")
    .accessibilityValue("\(Formatting.duration(player.currentTime)) of \(Formatting.duration(player.duration))")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: player.skip(by: 5)
      case .decrement: player.skip(by: -5)
      @unknown default: break
      }
    }
  }

  private func segmentBlock(_ clip: ClipMeta, index: Int, layout: TimelineLayout) -> some View {
    let isSelected = clip.name == selectedSegment
    let levels = folder.map { WaveformCache.shared.levels(for: $0.appending(path: clip.name), clip: clip) } ?? clip.waveform

    return RoundedRectangle(cornerRadius: 8)
      .fill(Color.paperAlt)
      .overlay {
        WaveformView(
          levels: levels,
          progress: layout.localProgress(of: index, at: player.currentTime),
          barWidth: 2,
          spacing: 1
        )
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
      }
      .overlay(alignment: .topLeading) {
        Text("\(index + 1)")
          .font(.caption2.weight(.bold).monospacedDigit())
          .foregroundStyle(Color.inkSoft)
          .padding(5)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(isSelected ? Color.accentColor : Color.line, lineWidth: isSelected ? 2 : 1)
      }
  }
}

private struct Playhead: View {
  let height: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      Image(systemName: "arrowtriangle.down.fill")
        .font(.system(size: 10))
        .foregroundStyle(Color.accentColor)
        .frame(width: 12, height: 8)
      Rectangle()
        .fill(Color.accentColor)
        .frame(width: 2, height: height - 8)
    }
    .frame(width: 12)
  }
}

struct TimelineLayout {
  let widths: [CGFloat]
  let starts: [CGFloat]
  let times: [Double]
  let durations: [Double]
  let width: CGFloat

  init(segments: [ClipMeta], player: SegmentPlayer, width: CGFloat, gap: CGFloat) {
    let actual: [Double]

    if player.boundaries.count == segments.count, player.duration > 0 {
      actual = player.boundaries.indices.map { index in
        let end = index + 1 < player.boundaries.count ? player.boundaries[index + 1] : player.duration
        return max(end - player.boundaries[index], 0)
      }
    } else {
      actual = segments.map(\.durationSeconds)
    }

    let total = max(actual.reduce(0, +), 0.001)
    let available = max(width - gap * CGFloat(max(segments.count - 1, 0)), 1)
    var widths: [CGFloat] = []
    var starts: [CGFloat] = []
    var times: [Double] = []
    var cursorX: CGFloat = 0
    var cursorTime = 0.0

    for duration in actual {
      starts.append(cursorX)
      times.append(cursorTime)
      let segmentWidth = available * CGFloat(duration / total)
      widths.append(segmentWidth)
      cursorX += segmentWidth + gap
      cursorTime += duration
    }

    self.widths = widths
    self.starts = starts
    self.times = times
    self.durations = actual
    self.width = width
  }

  func frame(of index: Int) -> CGRect {
    CGRect(x: starts[index], y: 0, width: widths[index], height: 0)
  }

  func x(at time: Double) -> CGFloat {
    guard let index = times.lastIndex(where: { $0 <= time + 0.0001 }) else { return 0 }
    let local = durations[index] > 0 ? min(max((time - times[index]) / durations[index], 0), 1) : 0
    return starts[index] + widths[index] * CGFloat(local)
  }

  func time(at x: CGFloat) -> Double {
    guard !starts.isEmpty else { return 0 }

    let index = starts.lastIndex { $0 <= x } ?? 0
    let local = widths[index] > 0 ? min(max((x - starts[index]) / widths[index], 0), 1) : 0
    return times[index] + durations[index] * Double(local)
  }

  func localProgress(of index: Int, at time: Double) -> Double {
    guard durations.indices.contains(index), durations[index] > 0 else { return 0 }
    return min(max((time - times[index]) / durations[index], 0), 1)
  }
}
