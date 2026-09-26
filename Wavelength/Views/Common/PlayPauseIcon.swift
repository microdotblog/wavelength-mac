import SwiftUI

struct PlayPauseIcon: View {
  let isPlaying: Bool
  var size: CGFloat = 16

  var body: some View {
    PlayPauseGlyph(progress: isPlaying ? 1 : 0)
      .fill()
      .frame(width: size, height: size)
      .animation(.spring(duration: 0.22, bounce: 0.15), value: isPlaying)
      .accessibilityLabel(isPlaying ? "Pause" : "Play")
  }
}

struct PlayPauseCircle: View {
  let isPlaying: Bool
  var size: CGFloat = 30

  var body: some View {
    PlayPauseIcon(isPlaying: isPlaying, size: size * 0.4)
      .foregroundStyle(.white)
      .offset(x: isPlaying ? 0 : size * 0.03)
      .frame(width: size, height: size)
      .background(Color.accentColor, in: .circle)
      .animation(.spring(duration: 0.22, bounce: 0.15), value: isPlaying)
  }
}

nonisolated private struct PlayPauseGlyph: Shape {
  var progress: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  private static let play: [[CGPoint]] = [
    [CGPoint(x: 0.12, y: 0), CGPoint(x: 0.55, y: 0.25), CGPoint(x: 0.55, y: 0.75), CGPoint(x: 0.12, y: 1)],
    [CGPoint(x: 0.55, y: 0.25), CGPoint(x: 0.98, y: 0.5), CGPoint(x: 0.98, y: 0.5), CGPoint(x: 0.55, y: 0.75)],
  ]

  private static let pause: [[CGPoint]] = [
    [CGPoint(x: 0.1, y: 0), CGPoint(x: 0.4, y: 0), CGPoint(x: 0.4, y: 1), CGPoint(x: 0.1, y: 1)],
    [CGPoint(x: 0.6, y: 0), CGPoint(x: 0.9, y: 0), CGPoint(x: 0.9, y: 1), CGPoint(x: 0.6, y: 1)],
  ]

  func path(in rect: CGRect) -> Path {
    var path = Path()

    for (playPiece, pausePiece) in zip(Self.play, Self.pause) {
      let points = zip(playPiece, pausePiece).map { from, to in
        CGPoint(
          x: rect.minX + (from.x + (to.x - from.x) * progress) * rect.width,
          y: rect.minY + (from.y + (to.y - from.y) * progress) * rect.height
        )
      }

      path.addLines(points)
      path.closeSubpath()
    }

    return path.union(path.strokedPath(StrokeStyle(lineWidth: rect.width * 0.08, lineJoin: .round)))
  }
}
