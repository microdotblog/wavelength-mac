import SwiftUI

struct SettingsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      AccountSettings()
      Divider()
      RecordingSettings()
    }
    .padding(24)
    .frame(width: 470)
    .navigationTitle("Settings")
  }
}

private struct AccountSettings: View {
  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session

  var body: some View {
    if session.isSignedIn {
      HStack(spacing: 14) {
        AvatarView(url: session.profile?.photo, size: 52)
        VStack(alignment: .leading, spacing: 2) {
          Text(session.displayName)
            .font(.title3.weight(.semibold))
          if let username = session.profile?.username {
            Text("@\(username)")
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button("Sign Out", role: .destructive) { model.confirmSignOut() }
      }
    } else {
      Text("You’re not signed in to Micro.blog.")
        .foregroundStyle(.secondary)
    }
  }
}

private struct RecordingSettings: View {
  @AppStorage(Recorder.inputDeviceDefaultsKey) private var deviceUID = ""
  @AppStorage("teleprompterFontSize") private var fontSize = 20
  @State private var devices: [InputDevice] = []

  private let textSizes: [(name: String, points: Int)] = [
    ("Tiny", 14),
    ("Small", 16),
    ("Medium", 20),
    ("Large", 30),
    ("Huge", 40)
  ]

  private var microphones: [(name: String, value: String)] {
    [(InputDevices.defaultName.map { "System Default (\($0))" } ?? "System Default", "")]
      + devices.map { (name: $0.name, value: $0.uid) }
  }

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
      GridRow {
        Text("Microphone:")
          .fixedSize()
          .gridColumnAlignment(.trailing)
        SettingsPopUpButton(label: "Microphone:", selection: $deviceUID, options: microphones)
          .frame(width: 296)
      }

      GridRow {
        Text("Narration text size:")
          .fixedSize()
        SettingsPopUpButton(
          label: "Narration text size:",
          selection: $fontSize,
          options: textSizes.map { (name: $0.name, value: $0.points) }
        )
        .frame(width: 296)
      }
    }
    .onAppear {
      devices = InputDevices.all()
      fontSize = textSizes.min { abs($0.points - fontSize) < abs($1.points - fontSize) }?.points ?? 20
    }
  }
}

private struct SettingsPopUpButton<Value: Equatable>: NSViewRepresentable {
  let label: String
  @Binding var selection: Value
  let options: [(name: String, value: Value)]

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectOption(_:))
    button.setAccessibilityLabel(label)
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection
    context.coordinator.values = options.map(\.value)
    let titles = options.map(\.name)
    if button.itemTitles != titles {
      button.removeAllItems()
      button.addItems(withTitles: titles)
    }
    button.selectItem(at: options.firstIndex { $0.value == selection } ?? -1)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  final class Coordinator: NSObject {
    var selection: Binding<Value>
    var values: [Value] = []

    init(selection: Binding<Value>) {
      self.selection = selection
    }

    @objc func selectOption(_ sender: NSPopUpButton) {
      let index = sender.indexOfSelectedItem
      guard values.indices.contains(index) else { return }
      selection.wrappedValue = values[index]
    }
  }
}
