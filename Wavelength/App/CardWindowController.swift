import AppKit
import SwiftUI

final class CardWindowController {
  static let shadowMargin: CGFloat = 48

  private var window: CardWindow?

  var isVisible: Bool { window?.isVisible ?? false }

  func show(title: String, centeredOn frame: NSRect? = nil, @ViewBuilder content: () -> some View) {
    if window == nil {
      let hosting = NSHostingView(rootView: content()
        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
        .padding(Self.shadowMargin))
      let card = CardWindow(
        contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      card.isReleasedWhenClosed = false
      card.isOpaque = false
      card.backgroundColor = .clear
      card.hasShadow = false
      card.isMovableByWindowBackground = true
      card.title = title
      card.contentView = hosting
      position(card, centeredOn: frame)
      window = card
    }

    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func close() {
    window?.close()
    window = nil
  }

  private func position(_ window: NSWindow, centeredOn frame: NSRect?) {
    guard let area = frame ?? (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }

    window.setFrameOrigin(NSPoint(
      x: (area.midX - window.frame.width / 2).rounded(),
      y: (area.midY - window.frame.height / 2).rounded()
    ))
  }
}

private final class CardWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
