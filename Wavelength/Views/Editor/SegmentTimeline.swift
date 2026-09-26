import AppKit
import SwiftUI

private let timelineSpace = "SegmentTimeline"

@Observable
final class TimelineViewport {
  static let maxPointsPerSecond: CGFloat = 300

  private(set) var zoom: CGFloat = 1
  private(set) var offset: CGFloat = 0
  @ObservationIgnored weak var hostView: NSView?
  var width: CGFloat = 0 { didSet { clamp() } }
  var duration: Double = 0 { didSet { clamp() } }

  var contentWidth: CGFloat { width * zoom }

  var maxZoom: CGFloat {
    guard width > 0, duration > 0 else { return 1 }
    return max(1, CGFloat(duration) * Self.maxPointsPerSecond / width)
  }

  func setZoom(_ value: CGFloat, anchor: CGFloat? = nil) {
    let screenX = anchor ?? width / 2
    let fraction = contentWidth > 0 ? (offset + screenX) / contentWidth : 0
    zoom = value
    clamp()
    offset = fraction * contentWidth - screenX
    clamp()
  }

  func zoom(by factor: CGFloat, around time: Double) {
    setZoom(zoom * factor, anchor: screenX(at: time))
  }

  func screenX(at time: Double) -> CGFloat? {
    guard duration > 0 else { return nil }
    let x = CGFloat(time / duration) * contentWidth - offset
    return (0...width).contains(x) ? x : nil
  }

  func scroll(by delta: CGFloat) {
    offset += delta
    clamp()
  }

  func scroll(to offset: CGFloat) {
    self.offset = offset
    clamp()
  }

  func reveal(_ x: CGFloat) {
    guard zoom > 1, x < offset || x > offset + width - 24 else { return }
    offset = x - width * 0.1
    clamp()
  }

  private func clamp() {
    zoom = min(max(zoom, 1), maxZoom)
    offset = min(max(offset, 0), max(contentWidth - width, 0))
  }
}

struct SegmentTimeline<Menu: View>: View {
  let segments: [ClipMeta]
  let folder: URL?
  let player: SegmentPlayer
  let viewport: TimelineViewport
  @Binding var selection: String?
  @Binding var range: ClosedRange<Double>?
  let canReorder: Bool
  let move: (Int, Int) -> Void
  let delete: () -> Void
  @ViewBuilder var menu: (ClipMeta, Int) -> Menu

  @State private var hoverLocation: CGFloat?
  @State private var drag: SegmentDrag?
  @State private var sweepStart: SweepStart?
  @State private var scrollMonitor: Any?
  @GestureState private var pinchBase: CGFloat?
  @FocusState private var isFocused: Bool
  private let gap: CGFloat = 2
  private let rulerHeight: CGFloat = 20
  private let stripHeight: CGFloat = 24

  var body: some View {
    GeometryReader { geometry in
      let layout = TimelineLayout(segments: segments, player: player, width: viewport.contentWidth, gap: gap)
      let width = geometry.size.width
      let regionHeight = geometry.size.height - rulerHeight
      let levels = segments.map(levels(of:))
      let gain = Self.gain(for: segments.map(\.waveform))

      ZStack(alignment: .topLeading) {
        TimeRuler(layout: layout, duration: layout.total, offset: viewport.offset)
          .frame(width: width, height: rulerHeight)
          .contentShape(.rect)
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                player.seek(to: time(at: value.location.x, layout))
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
          let minX = frame.minX + (isMoving ? drag?.offset ?? 0 : 0) - viewport.offset
          let visibleMin = max(minX, 0)
          let visibleMax = min(minX + frame.width, width)

          if visibleMax > visibleMin || isMoving {
            let isClipped = !isMoving && frame.width > 0
            let window = isClipped ? Double((visibleMin - minX) / frame.width)...Double((visibleMax - minX) / frame.width) : 0...1

            region(clip, index: index, levels: levels[index], gain: gain, window: window, layout: layout)
              .frame(width: max(isMoving ? frame.width : visibleMax - visibleMin, 1), height: regionHeight)
              .contentShape(.rect)
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
              .gesture(sweep(clip, layout: layout))
              .simultaneousGesture(TapGesture(count: 2).onEnded { player.play() })
              .shadow(color: .black.opacity(isMoving ? 0.25 : 0), radius: 8, y: 2)
              .zIndex(isMoving ? 1 : 0)
              .offset(x: isMoving ? minX : visibleMin, y: rulerHeight)
          }
        }

        if let range {
          selectionOverlay(range, layout: layout, height: regionHeight)
        }

        if let drag, drag.isMoving, drag.target != drag.index {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: 3, height: regionHeight)
            .offset(x: insertionX(for: drag, layout: layout) - viewport.offset - 1.5, y: rulerHeight)
            .allowsHitTesting(false)
        }

        if let hoverLocation, drag?.isMoving != true {
          Rectangle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 1, height: regionHeight)
            .offset(x: hoverLocation, y: rulerHeight)
            .allowsHitTesting(false)

          Text(Formatting.preciseDuration(time(at: hoverLocation, layout)))
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.background, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }
            .offset(x: min(max(hoverLocation + 4, 0), width - 52), y: rulerHeight + stripHeight + 4)
            .allowsHitTesting(false)
        }

        let playheadX = layout.x(at: player.currentTime) - viewport.offset

        if (-6...(width + 6)).contains(playheadX) {
          Playhead(height: geometry.size.height)
            .offset(x: playheadX - 6)
            .allowsHitTesting(false)
        }

        if viewport.zoom > 1 {
          scrollIndicator(width: width)
            .offset(y: geometry.size.height - 8)
        }
      }
      .frame(width: width, height: geometry.size.height, alignment: .topLeading)
      .clipped()
      .background(HostViewReader(viewport: viewport))
      .coordinateSpace(.named(timelineSpace))
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          hoverLocation = min(max(location.x, 0), width)
        case .ended:
          hoverLocation = nil
        }
      }
      .onChange(of: width, initial: true) { _, width in
        viewport.width = width
      }
      .onChange(of: layout.total, initial: true) { _, total in
        viewport.duration = total
      }
      .onChange(of: player.currentTime) { _, time in
        if player.isPlaying {
          viewport.reveal(layout.x(at: time))
        }
      }
      .onChange(of: segments.map(\.id)) {
        drag = nil
      }
    }
    .simultaneousGesture(
      MagnifyGesture()
        .updating($pinchBase) { value, base, _ in
          let start = base ?? viewport.zoom
          base = start
          viewport.setZoom(start * value.magnification, anchor: value.startLocation.x)
        }
    )
    .focusable(interactions: .edit)
    .focused($isFocused)
    .focusEffectDisabled()
    .onDeleteCommand(perform: delete)
    .onExitCommand { range = nil }
    .onAppear(perform: installScrollMonitor)
    .onDisappear(perform: removeScrollMonitor)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Timeline")
  }

  private func time(at screenX: CGFloat, _ layout: TimelineLayout) -> Double {
    layout.time(at: min(max(screenX, 0), viewport.width) + viewport.offset)
  }

  private func sweep(_ clip: ClipMeta, layout: TimelineLayout) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineSpace))
      .onChanged { value in
        if sweepStart?.location != value.startLocation {
          let start = time(at: value.startLocation.x, layout)
          sweepStart = SweepStart(location: value.startLocation, time: start)
          selection = clip.name
          range = nil
          isFocused = true
          player.seek(to: start)
        }

        guard let anchor = sweepStart?.time, abs(value.translation.width) > 3 else { return }

        if value.location.x > viewport.width - 24 {
          viewport.scroll(by: 16)
        } else if value.location.x < 24 {
          viewport.scroll(by: -16)
        }

        let current = time(at: value.location.x, layout)
        range = min(anchor, current)...max(anchor, current)
      }
      .onEnded { _ in
        sweepStart = nil
        guard let range else { return }

        if range.upperBound - range.lowerBound < SegmentCarving.minimumPiece {
          self.range = nil
        } else {
          player.seek(to: range.lowerBound)
        }
      }
  }

  private func reorder(_ clip: ClipMeta, index: Int, layout: TimelineLayout) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineSpace))
      .onChanged { value in
        if drag?.index != index {
          drag = SegmentDrag(index: index)
          selection = clip.name
          range = nil
          isFocused = true
          player.seek(to: time(at: value.startLocation.x, layout))
        }

        guard canReorder, segments.count > 1 else { return }

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

  private func selectionOverlay(_ range: ClosedRange<Double>, layout: TimelineLayout, height: CGFloat) -> some View {
    let startX = layout.x(at: range.lowerBound) - viewport.offset
    let endX = layout.x(at: range.upperBound) - viewport.offset

    return Rectangle()
      .fill(Color.accentColor.opacity(0.22))
      .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: 1) }
      .overlay(alignment: .trailing) { Rectangle().fill(Color.accentColor).frame(width: 1) }
      .overlay(alignment: .bottom) {
        Text(Formatting.preciseDuration(range.upperBound - range.lowerBound))
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Color.accentColor, in: .rect(cornerRadius: 4))
          .fixedSize()
          .padding(.bottom, 16)
      }
      .frame(width: max(endX - startX, 1), height: height)
      .offset(x: startX, y: rulerHeight)
      .allowsHitTesting(false)
  }

  private func scrollIndicator(width: CGFloat) -> some View {
    let thumb = max(width / viewport.zoom, 24)
    let travel = max(width - thumb, 1)
    let span = max(viewport.contentWidth - viewport.width, 1)

    return Capsule()
      .fill(Color.secondary.opacity(0.55))
      .frame(width: thumb, height: 5)
      .contentShape(.rect.inset(by: -6))
      .offset(x: viewport.offset / span * travel)
      .gesture(
        DragGesture(coordinateSpace: .named(timelineSpace))
          .onChanged { value in
            viewport.scroll(to: (value.location.x - thumb / 2) / travel * span)
          }
      )
  }

  private func installScrollMonitor() {
    guard scrollMonitor == nil else { return }
    let viewport = viewport

    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      let windowNumber = event.windowNumber
      let point = event.locationInWindow
      let isZooming = event.modifierFlags.contains(.command)
      let precise = event.hasPreciseScrollingDeltas
      let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
      let wheel = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
      let distance = -delta * (precise ? 1 : 12)
      let factor = exp(wheel * (precise ? 0.01 : 0.12))

      let handled = MainActor.assumeIsolated {
        guard let view = viewport.hostView, view.window?.windowNumber == windowNumber else { return false }
        let local = view.convert(point, from: nil)
        guard view.bounds.contains(local) else { return false }

        if isZooming {
          viewport.setZoom(viewport.zoom * factor, anchor: local.x)
          return true
        }

        guard viewport.zoom > 1 else { return false }
        viewport.scroll(by: distance)
        return true
      }

      return handled ? nil : event
    }
  }

  private func removeScrollMonitor() {
    if let scrollMonitor {
      NSEvent.removeMonitor(scrollMonitor)
    }

    scrollMonitor = nil
  }

  private func levels(of clip: ClipMeta) -> [Float] {
    folder.map { WaveformCache.shared.levels(for: $0.appending(path: clip.name), clip: clip) } ?? clip.waveform
  }

  private static func gain(for levels: [[Float]]) -> Float {
    let peak = levels.joined().max() ?? 0
    return peak > 0 ? min(0.9 / peak, 6) : 1
  }

  private func region(
    _ clip: ClipMeta,
    index: Int,
    levels: [Float],
    gain: Float,
    window: ClosedRange<Double>,
    layout: TimelineLayout
  ) -> some View {
    let isSelected = range == nil && clip.name == selection
    let leading: CGFloat = window.lowerBound <= 0.0001 ? 6 : 0
    let trailing: CGFloat = window.upperBound >= 0.9999 ? 6 : 0
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: leading,
      bottomLeadingRadius: leading,
      bottomTrailingRadius: trailing,
      topTrailingRadius: trailing
    )
    let span = max(window.upperBound - window.lowerBound, 0.0001)
    let progress = (layout.localProgress(of: index, at: player.currentTime) - window.lowerBound) / span

    return shape
      .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
      .overlay {
        WaveformView(
          levels: Waveform.slice(levels, from: window.lowerBound, to: window.upperBound),
          progress: min(max(progress, 0), 1),
          barWidth: 2,
          spacing: 1,
          gain: gain
        )
        .padding(.top, stripHeight + 4)
        .padding(.bottom, 14)
        .padding(.horizontal, 4)
      }
      .overlay(alignment: .top) {
        strip(index: index, duration: layout.durations[index])
          .gesture(reorder(clip, index: index, layout: layout))
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 1)
      }
  }

  private func strip(index: Int, duration: Double) -> some View {
    ViewThatFits(in: .horizontal) {
      stripLabel("Segment \(index + 1)", duration: duration)
      stripLabel("\(index + 1)", duration: duration)
      stripLabel("\(index + 1)", duration: nil)
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, minHeight: stripHeight, maxHeight: stripHeight)
    .background(Color.primary.opacity(0.05))
    .contentShape(.rect)
    .pointerStyle(canReorder ? .grabIdle : nil)
    .help(canReorder ? "Drag to reorder" : "")
  }

  private func stripLabel(_ title: String, duration: Double?) -> some View {
    HStack(spacing: 6) {
      if canReorder {
        Image(systemName: "line.3.horizontal")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

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

private struct SweepStart {
  let location: CGPoint
  let time: Double
}

private struct HostViewReader: NSViewRepresentable {
  let viewport: TimelineViewport

  func makeNSView(context: Context) -> NSView {
    let view = PassthroughView()
    viewport.hostView = view
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    viewport.hostView = nsView
  }
}

private final class PassthroughView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
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
  let offset: CGFloat

  private static let intervals: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1_800, 3_600]

  var body: some View {
    Canvas { context, size in
      guard duration > 0, size.width > 0, layout.width > 0 else { return }

      let pointsPerSecond = layout.width / duration
      let major = Self.intervals.first { $0 * pointsPerSecond >= 64 } ?? Self.intervals.last!
      let minor = major / 5
      let showsMinor = minor * pointsPerSecond >= 8
      let step = showsMinor ? minor : major
      let ticksPerMajor = showsMinor ? 5 : 1
      var index = max(Int((layout.time(at: offset) / step).rounded(.down)) - 1, 0)
      var time = Double(index) * step

      while time <= duration + 0.001 {
        let x = (layout.x(at: time) - offset).rounded() + 0.5

        if x > size.width + 64 {
          break
        }

        let isMajor = index % ticksPerMajor == 0
        let tickHeight: CGFloat = isMajor ? 7 : 3
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: size.height - tickHeight))
        tick.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(tick, with: .color(.secondary.opacity(isMajor ? 0.7 : 0.4)), lineWidth: 1)

        if isMajor {
          context.draw(
            Text(major < 1 ? Formatting.preciseDuration(time) : Formatting.duration(time))
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary),
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

  var total: Double {
    (times.last ?? 0) + (durations.last ?? 0)
  }

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
