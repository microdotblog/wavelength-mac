import AppKit
import SwiftUI

final class SignInCard {
  static let shadowMargin: CGFloat = 48

  private var window: CardWindow?

  var isVisible: Bool { window?.isVisible ?? false }

  func show(_ model: AppModel) {
    if window == nil {
      let hosting = NSHostingView(rootView: SignInView()
        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
        .padding(Self.shadowMargin)
        .appEnvironment(model))
      let size = hosting.fittingSize
      let card = CardWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      card.isReleasedWhenClosed = false
      card.isOpaque = false
      card.backgroundColor = .clear
      card.hasShadow = false
      card.isMovableByWindowBackground = true
      card.title = "Sign In"
      card.contentView = hosting
      center(card)
      window = card
    }

    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func close() {
    window?.close()
    window = nil
  }

  private func center(_ window: NSWindow) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

    let visible = screen.visibleFrame
    window.setFrameOrigin(NSPoint(
      x: (visible.midX - window.frame.width / 2).rounded(),
      y: (visible.midY - window.frame.height / 2).rounded()
    ))
  }
}

private final class CardWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
