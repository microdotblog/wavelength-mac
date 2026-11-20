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
      WavelengthCommands(model: delegate.model, updates: delegate.updates)
    }

    Settings {
      SettingsView()
        .appEnvironment(delegate.model)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  let updates = SoftwareUpdates()

  func applicationDidFinishLaunching(_ notification: Notification) {
    updates.start()

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

  func body(content: Content) -> some View {
    content
      .background {
        MainWindowReader(model: model)
          .frame(width: 0, height: 0)
      }
      .task { await model.start() }
      .onChange(of: session.isHydrated && !session.isSignedIn, initial: true) { _, needsSignIn in
        if needsSignIn {
          model.showSignIn()
        }
      }
  }
}

private struct MainWindowReader: NSViewRepresentable {
  let model: AppModel

  func makeNSView(context: Context) -> WindowReaderView {
    let view = WindowReaderView()
    view.model = model
    return view
  }

  func updateNSView(_ nsView: WindowReaderView, context: Context) {}

  final class WindowReaderView: NSView {
    weak var model: AppModel?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      model?.mainWindow = window
    }
  }
}
