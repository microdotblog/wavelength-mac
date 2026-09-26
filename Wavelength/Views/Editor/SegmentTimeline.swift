import SwiftUI

private let timelineSpace = "SegmentTimeline"

struct SegmentTimeline<Menu: View>: View {
  let segments: [ClipMeta]
  let folder: URL?
  let player: SegmentPlayer
  @Binding var selection: String?
  let canReorder: Bool
  let move: (Int, Int) -> Void
  let delete: () -> Void
  @ViewBuilder var menu: (ClipMeta, Int) -> Menu

  @State private var hoverLocation: CGFloat?
  @State private var drag: SegmentDrag?
  @FocusState private var isFocused: Bool
  private let gap: CGFloat = 2
  private let rulerHeight: CGFloat = 20

  var body: some View {
    GeometryReader { geometry in
      let layout = TimelineLayout(segments: segments, player: player, width: geometry.size.width, gap: gap)
      let regionHeight = geometry.size.height - rulerHeight
      let levels = segments.map(levels(of:))
      let gain = Self.gain(for: levels)

      ZStack(alignment: .topLeading) {
        TimeRuler(layout: layout, duration: layout.times.last.map { $0 + (layout.durations.last ?? 0) } ?? 0)
          .frame(height: rulerHeight)
          .contentShape(.rect)
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                player.seek(to: layout.time(at: value.location.x))
              }
          )
          .accessibilityElement()
          .accessibilityLabel("Playhead")
          .accessibilityValue("\(Formatting.duration(player.currentTime)) of \(Formatting.duration(player.duration))")
          .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.skip(by: 5)
            case .decrement: player.skip(by: -5)
            @unknown default: break
            }
          }

        ForEach(Array(segments.enumerated()), id: \.element.id) { index, clip in
          let frame = layout.frame(of: index)
          let isMoving = drag?.index == index && drag?.isMoving == true

          region(clip, index: index, levels: levels[index], gain: gain, layout: layout)
            .frame(width: max(frame.width, 1), height: regionHeight)
            .contentShape(.rect(cornerRadius: 6))
            .contextMenu { menu(clip, index) }
            .accessibilityElement()
            .accessibilityLabel("Segment \(index + 1)")
            .accessibilityValue(Formatting.duration(layout.durations[index]))
            .accessibilityAddTraits(clip.name == selection ? .isSelected : [])
            .accessibilityAction {
              selection = clip.name
              player.seek(to: layout.times[index])
            }
            .accessibilityActions {
              if canReorder && index > 0 {
                Button("Move Earlier") { move(index, index - 1) }
              }

              if canReorder && index < segments.count - 1 {
                Button("Move Later") { move(index, index + 1) }
              }
            }
            .gesture(press(clip, index: index, layout: layout))
            .simultaneousGesture(TapGesture(count: 2).onEnded { player.play() })
            .shadow(color: .black.opacity(isMoving ? 0.25 : 0), radius: 8, y: 2)
            .zIndex(isMoving ? 1 : 0)
            .offset(x: frame.minX + (isMoving ? drag?.offset ?? 0 : 0), y: rulerHeight)
        }

        if let drag, drag.isMoving, drag.target != drag.index {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: 3, height: regionHeight)
            .offset(x: insertionX(for: drag, layout: layout) - 1.5, y: rulerHeight)
            .allowsHitTesting(false)
        }

        if let hoverLocation, drag?.isMoving != true {
          Rectangle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 1, height: regionHeight)
            .offset(x: hoverLocation, y: rulerHeight)
            .allowsHitTesting(false)

          Text(Formatting.preciseDuration(layout.time(at: hoverLocation)))
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.background, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }
            .offset(x: min(max(hoverLocation + 4, 0), geometry.size.width - 52), y: rulerHeight + 4)
            .allowsHitTesting(false)
        }

        Playhead(height: geometry.size.height)
          .offset(x: layout.x(at: player.currentTime) - 6)
          .allowsHitTesting(false)
      }
      .coordinateSpace(.named(timelineSpace))
      .onChange(of: segments.map(\.id)) {
        drag = nil
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let location): hoverLocation = min(max(location.x, 0), geometry.size.width)
        case .ended: hoverLocation = nil
        }
      }
    }
    .focusable(interactions: .edit)
    .focused($isFocused)
    .focusEffectDisabled()
    .onDeleteCommand(perform: delete)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Timeline")
  }

  private func press(_ clip: ClipMeta, index: Int, layout: TimelineLayout) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineSpace))
      .onChanged { value in
        if drag?.index != index {
          drag = SegmentDrag(index: index)
          selection = clip.name
          isFocused = true
          player.seek(to: layout.time(at: value.startLocation.x))
        }

        guard canReorder, segments.count > 1 else {
          player.seek(to: layout.time(at: value.location.x))
          return
        }

        if abs(value.translation.width) > 4 {
          drag?.isMoving = true
        }

        guard drag?.isMoving == true else { return }
        drag?.offset = value.translation.width
        drag?.target = target(for: index, center: layout.frame(of: index).midX + value.translation.width, layout: layout)
      }
      .onEnded { _ in
        if let drag, drag.isMoving, drag.target != drag.index {
          move(drag.index, drag.target)
        }

        drag = nil
      }
  }

  private func target(for index: Int, center: CGFloat, layout: TimelineLayout) -> Int {
    segments.indices.filter { $0 != index && layout.frame(of: $0).midX < center }.count
  }

  private func insertionX(for drag: SegmentDrag, layout: TimelineLayout) -> CGFloat {
    let others = segments.indices.filter { $0 != drag.index }

    if others.indices.contains(drag.target) {
      return max(layout.frame(of: others[drag.target]).minX - gap / 2, 1.5)
    }

    return min(others.last.map { layout.frame(of: $0).maxX + gap / 2 } ?? 0, layout.width - 1.5)
  }

  private func levels(of clip: ClipMeta) -> [Float] {
    folder.map { WaveformCache.shared.levels(for: $0.appending(path: clip.name), clip: clip) } ?? clip.waveform
  }

  private static func gain(for levels: [[Float]]) -> Float {
    let peak = levels.joined().max() ?? 0
    return peak > 0 ? min(0.9 / peak, 6) : 1
  }

  private func region(_ clip: ClipMeta, index: Int, levels: [Float], gain: Float, layout: TimelineLayout) -> some View {
    let isSelected = clip.name == selection

    return RoundedRectangle(cornerRadius: 6)
      .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
      .overlay {
        WaveformView(
          levels: levels,
          progress: layout.localProgress(of: index, at: player.currentTime),
          barWidth: 2,
          spacing: 1,
          gain: gain
        )
        .padding(.top, 26)
        .padding(.bottom, 14)
        .padding(.horizontal, 4)
      }
      .overlay(alignment: .top) {
        ViewThatFits(in: .horizontal) {
          regionLabel("Segment \(index + 1)", duration: layout.durations[index])
          regionLabel("\(index + 1)", duration: layout.durations[index])
          regionLabel("\(index + 1)", duration: nil)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
      }
      .clipShape(.rect(cornerRadius: 6))
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 1)
      }
  }

  private func regionLabel(_ title: String, duration: Double?) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.caption2.weight(.medium))

      if let duration {
        Spacer(minLength: 4)
        Text(Formatting.duration(duration))
          .font(.caption2.monospacedDigit())
      }
    }
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .fixedSize(horizontal: duration == nil, vertical: false)
  }
}

private struct SegmentDrag {
  let index: Int
  var target: Int
  var offset: CGFloat = 0
  var isMoving = false

  init(index: Int) {
    self.index = index
    target = index
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
