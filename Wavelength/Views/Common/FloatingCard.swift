import SwiftUI

struct CardBackdrop: View {
  var body: some View {
    ZStack {
      Color.canvas.opacity(0.55)

      RadialGradient(
        colors: [Color.accentColor.opacity(0.32), Color.gold.opacity(0.10), .clear],
        center: .top,
        startRadius: 10,
        endRadius: 360
      )
    }
  }
}

extension View {
  func floatingCard(width: CGFloat, height: CGFloat) -> some View {
    frame(width: width, height: height)
      .background {
        CardBackdrop()
          .gesture(WindowDragGesture())
          .allowsWindowActivationEvents(true)
      }
      .clipShape(.rect(cornerRadius: 30))
      .glassEffect(.regular, in: .rect(cornerRadius: 30))
  }
}
