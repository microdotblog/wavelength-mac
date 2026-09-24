import SwiftUI

enum WindowID {
  static let main = "main"
}

@main
struct WavelengthApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  private let startsSignedIn = Keychain.load().userToken.nonEmpty != nil

  var body: some Scene {
    Window("Wavelength", id: WindowID.main) {
      RootView()
        .frame(minWidth: 900, minHeight: 560)
        .modifier(MainWindowRouting())
        .appEnvironment(delegate.model)
        .onOpenURL { url in
          Task { await delegate.model.session.handleOpenURL(url) }
        }
    }
    .defaultSize(width: 1200, height: 760)
    .defaultLaunchBehavior(startsSignedIn ? .presented : .suppressed)
    .commands {
      WavelengthCommands(model: delegate.model)
    }

    Settings {
      SettingsView()
        .appEnvironment(delegate.model)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    if Keychain.load().userToken.nonEmpty == nil {
      model.showSignIn()
    }

    Task { await model.start() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    guard model.session.isHydrated, !model.session.isSignedIn else { return true }

    model.showSignIn()
    return false
  }
}

extension View {
  func appEnvironment(_ model: AppModel) -> some View {
    environment(model)
      .environment(model.session)
      .environment(model.library)
      .environment(model.posts)
      .environment(model.discover)
      .environment(model.nowPlaying)
      .environment(model.recorder)
      .environment(model.narration)
      .environment(model.toasts)
  }
}

private struct MainWindowRouting: ViewModifier {
  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(\.dismissWindow) private var dismissWindow

  func body(content: Content) -> some View {
    content
      .task {
        await model.start()
        route()
      }
      .onChange(of: session.isSignedIn) {
        route()
      }
  }

  private func route() {
    guard session.isHydrated, !session.isSignedIn else { return }

    model.showSignIn()
    dismissWindow(id: WindowID.main)
  }
}
