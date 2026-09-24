import SwiftUI

struct SegmentTimeline: View {
  let segments: [ClipMeta]
  let folder: URL?
  let player: SegmentPlayer
  var selectedSegment: String?
  var height: CGFloat = 150

  @State private var hoverLocation: CGFloat?
  private let gap: CGFloat = 2
  private let rulerHeight: CGFloat = 20

  var body: some View {
    GeometryReader { geometry in
      let layout = TimelineLayout(segments: segments, player: player, width: geometry.size.width, gap: gap)
      let regionHeight = geometry.size.height - rulerHeight

      ZStack(alignment: .topLeading) {
        TimeRuler(layout: layout, duration: layout.times.last.map { $0 + (layout.durations.last ?? 0) } ?? 0)
          .frame(height: rulerHeight)

        ForEach(Array(segments.enumerated()), id: \.element.id) { index, clip in
          let frame = layout.frame(of: index)
          region(clip, index: index, layout: layout)
            .frame(width: max(frame.width, 1), height: regionHeight)
            .offset(x: frame.minX, y: rulerHeight)
        }

        if let hoverLocation {
          Rectangle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 1, height: regionHeight)
            .offset(x: hoverLocation, y: rulerHeight)

          Text(Formatting.preciseDuration(layout.time(at: hoverLocation)))
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.background, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }
            .offset(x: min(max(hoverLocation + 4, 0), geometry.size.width - 52), y: rulerHeight + 4)
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

  private func region(_ clip: ClipMeta, index: Int, layout: TimelineLayout) -> some View {
    let isSelected = clip.name == selectedSegment
    let levels = folder.map { WaveformCache.shared.levels(for: $0.appending(path: clip.name), clip: clip) } ?? clip.waveform

    return RoundedRectangle(cornerRadius: 6)
      .fill(Color.accentColor.opacity(isSelected ? 0.14 : 0.07))
      .overlay {
        WaveformView(
          levels: levels,
          progress: layout.localProgress(of: index, at: player.currentTime),
          barWidth: 2,
          spacing: 1
        )
        .padding(.top, 18)
        .padding(.bottom, 8)
        .padding(.horizontal, 4)
      }
      .overlay(alignment: .topLeading) {
        Text("Segment \(index + 1)")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor), lineWidth: 1)
      }
  }
}

private struct TimeRuler: View {
  let layout: TimelineLayout
  let duration: Double

  private static let intervals: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1_800, 3_600]

  var body: some View {
    Canvas { context, size in
      guard duration > 0, size.width > 0 else { return }

      let pointsPerSecond = size.width / duration
      let major = Self.intervals.first { $0 * pointsPerSecond >= 64 } ?? Self.intervals.last!
      let minor = major / 5
      let showsMinor = minor * pointsPerSecond >= 8
      let step = showsMinor ? minor : major
      var time = 0.0
      var index = 0

      while time <= duration + 0.001 {
        let x = layout.x(at: time).rounded() + 0.5
        let isMajor = index % (showsMinor ? 5 : 1) == 0
        let tickHeight: CGFloat = isMajor ? 7 : 3
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: size.height - tickHeight))
        tick.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(tick, with: .color(.secondary.opacity(isMajor ? 0.7 : 0.4)), lineWidth: 1)

        if isMajor {
          context.draw(
            Text(Formatting.duration(time)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
            at: CGPoint(x: x + 3, y: 1),
            anchor: .topLeading
          )
        }

        index += 1
        time = Double(index) * step
      }
    }
    .accessibilityHidden(true)
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
        .frame(width: 1.5, height: height - 8)
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
