import SwiftUI

struct WaveformView: View {
  var levels: [Float]
  var progress: Double = 0
  var barWidth: CGFloat = 2
  var spacing: CGFloat = 1.5
  var played: Color = .accentColor
  var unplayed: Color = .inkSoft.opacity(0.35)
  var minimumBar: CGFloat = 1.5

  var body: some View {
    Canvas { context, size in
      let stride = barWidth + spacing
      let count = max(1, Int((size.width + spacing) / stride))
      let bars = Waveform.resample(levels, to: count)
      let playedWidth = size.width * progress
      let middle = size.height / 2

      for (index, level) in bars.enumerated() {
        let x = CGFloat(index) * stride
        let height = max(minimumBar, CGFloat(level) * size.height)
        let rect = CGRect(x: x, y: middle - height / 2, width: barWidth, height: height)
        let color = x + barWidth / 2 <= playedWidth ? played : unplayed
        context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
      }
    }
    .accessibilityHidden(true)
  }
}

struct LiveWaveformView: View {
  var levels: [Float]
  var color: Color = .recording
  var barWidth: CGFloat = 3
  var spacing: CGFloat = 2

  var body: some View {
    Canvas { context, size in
      let stride = barWidth + spacing
      let count = max(1, Int((size.width + spacing) / stride))
      let visible = Array(levels.suffix(count))
      let offset = CGFloat(count - visible.count) * stride
      let middle = size.height / 2

      for (index, level) in visible.enumerated() {
        let x = offset + CGFloat(index) * stride
        let height = max(2, CGFloat(level) * size.height)
        let rect = CGRect(x: x, y: middle - height / 2, width: barWidth, height: height)
        let fade = 0.35 + 0.65 * Double(index + 1) / Double(max(visible.count, 1))
        context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(fade)))
      }
    }
    .accessibilityHidden(true)
  }
}
