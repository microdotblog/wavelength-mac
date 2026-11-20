import AppKit
import ObjectiveC.runtime

// Based on Brent Simmons’s NSMenuItem+RSCore in Micro.blog for Mac.
extension NSMenuItem {
  static func disableMenuIcons() {
    _ = menuIconSwizzle
  }

  private static let menuIconSwizzle: Void = {
    guard let original = class_getInstanceMethod(NSMenuItem.self, #selector(getter: NSMenuItem.image)),
          let replacement = class_getInstanceMethod(NSMenuItem.self, #selector(wavelengthMenuItemImage)) else { return }

    method_exchangeImplementations(original, replacement)
  }()

  @objc private dynamic func wavelengthMenuItemImage() -> NSImage? {
    // After the exchange, this selector calls the original image getter.
    guard !title.isEmpty, let menu else { return wavelengthMenuItemImage() }

    let mainMenu = NSApplication.shared.mainMenu
    if menu.supermenu === mainMenu {
      return nil
    }

    // Context menus have their own root. Nested main-menu items keep their images.
    var rootMenu = menu
    while let parent = rootMenu.supermenu {
      rootMenu = parent
    }
    return rootMenu === mainMenu ? wavelengthMenuItemImage() : nil
  }
}
