import AppKit
import SwiftUI

extension Color {
  static let canvas = Color(light: 0xFFFAF0, dark: 0x15100B)
  static let paper = Color(light: 0xFFFFFF, dark: 0x21180F)
  static let ink = Color(light: 0x24180D, dark: 0xFFF7E8)
  static let inkSoft = Color(light: 0x756657, dark: 0xD9C0A8)
  static let line = Color(red: 1, green: 136 / 255, blue: 0).opacity(0.2)
  static let gold = Color(hex: 0xFFC400)

  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  init(light: UInt32, dark: UInt32) {
    self.init(nsColor: NSColor(name: nil) { appearance in
      let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      return NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
    })
  }
}
