import SwiftUI

struct WaveformView: View {
  var levels: [Float]
  var progress: Double = 0
  var barWidth: CGFloat = 2
  var spacing: CGFloat = 1.5
  var played: Color = .accentColor
  var unplayed: Color = Color(nsColor: .tertiaryLabelColor)
  var minimumBar: CGFloat = 1.5
  var gain: Float = 1

  var body: some View {
    Canvas { context, size in
      let stride = barWidth + spacing
      let count = max(1, Int((size.width + spacing) / stride))
      let bars = Waveform.resample(levels, to: count)
      let playedWidth = size.width * progress
      let middle = size.height / 2

      for (index, level) in bars.enumerated() {
        let x = CGFloat(index) * stride
        let height = max(minimumBar, CGFloat(min(level * gain, 1)) * size.height)
        let rect = CGRect(x: x, y: middle - height / 2, width: barWidth, height: height)
        let color = x + barWidth / 2 <= playedWidth ? played : unplayed
        context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
      }
    }
    .accessibilityHidden(true)
  }
}

struct LiveWaveformView: View {
  static let peakLevel: Float = 0.7
  static let latency = 0.2

  var levels: [Float]
  var endTime: Double = 0
  var receivedAt = Date()
  var isRunning = false
  var barWidth: CGFloat = 3
  var spacing: CGFloat = 2

  var body: some View {
    TimelineView(.animation(paused: !isRunning)) { timeline in
      Canvas { context, size in
        if levels.isEmpty {
          drawIdle(in: &context, size: size)
        } else {
          drawLive(in: &context, size: size, now: timeline.date)
        }
      }
    }
    .accessibilityHidden(true)
  }

  private func drawLive(in context: inout GraphicsContext, size: CGSize, now: Date) {
    let stride = barWidth + spacing
    let pixelsPerSecond = stride / Recorder.levelInterval
    let lag = min(max(now.timeIntervalSince(receivedAt), 0), Self.latency)
    let head = endTime + lag - Self.latency
    let fadeWidth = size.width * 0.14

    for (offset, level) in levels.reversed().enumerated() {
      let time = endTime - Double(offset + 1) * Recorder.levelInterval

      guard time <= head else { continue }

      let x = size.width - CGFloat(head - time) * pixelsPerSecond - barWidth

      if x < -barWidth {
        break
      }

      let edge = min(1, max(0, x / max(fadeWidth, 1)))
      draw(level, at: x, edge: edge, in: &context, size: size)
    }
  }

  private func drawIdle(in context: inout GraphicsContext, size: CGSize) {
    let stride = barWidth + spacing
    let count = Int((size.width + spacing) / stride)
    let middle = size.height / 2

    for index in 0..<max(count, 0) {
      let rect = CGRect(x: CGFloat(index) * stride, y: middle - 2, width: barWidth, height: 4)
      context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(Color.accentColor.opacity(0.18)))
    }
  }

  private func draw(_ level: Float, at x: CGFloat, edge: CGFloat, in context: inout GraphicsContext, size: CGSize) {
    let clamped = Waveform.clamp(level)
    let height = max(4, CGFloat(clamped) * size.height)
    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
    let base = clamped >= Self.peakLevel ? Color.gold : Color.accentColor
    let opacity = Double(0.35 + clamped * 0.65) * Double(edge)
    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(base.opacity(opacity)))
  }
}
