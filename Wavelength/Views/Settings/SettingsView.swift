import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      Tab("Account", systemImage: "person.crop.circle") {
        AccountSettings()
      }

      Tab("Recording", systemImage: "mic") {
        RecordingSettings()
      }
    }
    .frame(width: 500)
    .scenePadding()
  }
}

private struct AccountSettings: View {
  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(\.openURL) private var openURL
  @State private var isConfirmingSignOut = false

  var body: some View {
    Form {
      if session.isSignedIn {
        Section {
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
            if let url = session.profile?.url {
              Button("View Profile") { openURL(url) }
            }
          }
        }

        Section("Blog") {
          if session.destinations.isEmpty {
            HStack {
              Text(session.destinationName)
              Spacer()
              if session.isLoadingDestinations {
                ProgressView().controlSize(.small)
              } else {
                Button("Reload") { Task { await session.loadDestinations() } }
              }
            }

            if let message = session.destinationErrorMessage {
              Text(message).foregroundStyle(.red).font(.callout)
            }
          } else {
            Picker("Publish to", selection: Binding(
              get: { session.selectedDestination?.uid ?? "" },
              set: { uid in
                if let destination = session.destinations.first(where: { $0.uid == uid }) {
                  session.select(destination)
                  Task { await model.posts.refresh() }
                }
              }
            )) {
              ForEach(session.destinations) { destination in
                Text(destination.name).tag(destination.uid)
              }
            }
          }
        }

        Section {
          Link("Community Guidelines", destination: URL(string: "https://help.micro.blog/t/community-guidelines/39")!)
          Link("Privacy Policy", destination: URL(string: "https://help.micro.blog/t/privacy-policy/114")!)
          Link("Delete Account…", destination: URL(string: "https://micro.blog/account/delete")!)
        }

        Section {
          Button("Sign Out…", role: .destructive) { isConfirmingSignOut = true }
        }
      } else {
        Text("You’re not signed in to Micro.blog.")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .confirmationDialog("Sign out of Wavelength?", isPresented: $isConfirmingSignOut) {
      Button("Sign Out", role: .destructive) { model.signOut() }
    } message: {
      Text("Your episodes stay on this Mac.")
    }
  }
}

private struct RecordingSettings: View {
  @AppStorage(Recorder.inputDeviceDefaultsKey) private var deviceUID = ""
  @AppStorage("teleprompterFontSize") private var fontSize = 20
  @State private var devices: [InputDevice] = []

  var body: some View {
    Form {
      Section {
        Picker("Microphone", selection: $deviceUID) {
          Text(InputDevices.defaultName.map { "System Default (\($0))" } ?? "System Default").tag("")
          ForEach(devices) { device in
            Text(device.name).tag(device.uid)
          }
        }
      } footer: {
        Text("Segments are saved as 44.1 kHz AAC. Wavelength converts the finished episode to a 128 kbps MP3 when you publish.")
          .foregroundStyle(.secondary)
      }

      Section("Narration") {
        Stepper("Teleprompter text size: \(fontSize) pt", value: $fontSize, in: 14...40, step: 2)
      }
    }
    .formStyle(.grouped)
    .onAppear { devices = InputDevices.all() }
  }
}
