import AuthenticationServices
import SwiftUI

struct SignInView: View {
  enum Mode {
    case welcome
    case token
  }

  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession
  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mode = Mode.welcome
  @State private var isCardShown = false
  @State private var isButtonShown = false
  @State private var token = ""
  @FocusState private var isTokenFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(14)

      Group {
        switch mode {
        case .welcome: welcome
        case .token: tokenEntry
        }
      }
      .transition(.blurReplace)
      .padding(.horizontal, 32)
      .padding(.bottom, 28)
    }
    .floatingCard(width: 380, height: 540)
    .scaleEffect(isCardShown || reduceMotion ? 1 : 0.94)
    .offset(y: isCardShown || reduceMotion ? 0 : 14)
    .opacity(isCardShown ? 1 : 0)
    .animation(.spring(duration: 0.4), value: mode)
    .onAppear {
      Task { animateIn() }
    }
    .onExitCommand {
      if mode == .token {
        showWelcome()
      }
    }
    .onChange(of: session.isSignedIn) { _, isSignedIn in
      if isSignedIn {
        model.showMainWindow()
      }
    }
  }

  private var header: some View {
    HStack {
      if mode == .token {
        Button(action: showWelcome) {
          Image(systemName: "chevron.left")
        }
        .help("Back")
      } else {
        Button {
          NSApp.terminate(nil)
        } label: {
          Image(systemName: "xmark")
        }
        .help("Quit Wavelength")
      }

      Spacer()

      Menu {
        Button("Sign in with an App Token…", systemImage: "key") { showToken() }
        Divider()
        Button("Get a Micro.blog Account", systemImage: "person.badge.plus") {
          openURL(URL(string: "https://micro.blog/register")!)
        }
        Button("Quit Wavelength", systemImage: "power") { NSApp.terminate(nil) }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuIndicator(.hidden)
      .help("More sign-in options")
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .controlSize(.large)
    .focusEffectDisabled()
    .disabled(session.isBusy)
  }

  private var welcome: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      ZStack {
        AnimatedWaveform()
          .frame(height: 96)
          .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))

        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 112, height: 112)
          .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
      }
      .padding(.bottom, 22)

      Text("WAVELENGTH")
        .font(.caption.weight(.heavy))
        .tracking(2.4)
        .foregroundStyle(Color.accentColor)
        .padding(.bottom, 8)

      Text("Record, edit, and publish podcasts.")
        .font(.system(size: 25, weight: .bold, design: .rounded))
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)

      Text("Sign in with Micro.blog to get started.")
        .font(.callout)
        .foregroundStyle(Color.inkSoft)

      Spacer(minLength: 0)

      Button(action: signInWithMicroBlog) {
        HStack(spacing: 8) {
          if session.phase == .connecting {
            ProgressView().controlSize(.small).tint(.white)
          } else {
            Image("MicroBlogLogo")
              .resizable()
              .frame(width: 20, height: 20)
          }
          Text(session.phase == .connecting ? "Waiting for Micro.blog…" : "Sign in with Micro.blog")
        }
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PrimaryCapsuleButtonStyle())
      .keyboardShortcut(.defaultAction)
      .disabled(session.isBusy)
      .offset(y: isButtonShown || reduceMotion ? 0 : 36)
      .opacity(isButtonShown ? 1 : 0)

      errorMessage
        .frame(height: 44)
    }
  }

  private var tokenEntry: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      Image(systemName: "key.fill")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 72, height: 72)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.15)), in: .circle)
        .padding(.bottom, 20)

      Text("Sign in with a token")
        .font(.system(size: 25, weight: .bold, design: .rounded))
        .foregroundStyle(Color.ink)
        .padding(.bottom, 8)

      Text("Paste a Micro.blog app token from your account page.")
        .font(.callout)
        .foregroundStyle(Color.inkSoft)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 22)

      SecureField("App token", text: $token)
        .textFieldStyle(.plain)
        .font(.body.monospaced())
        .focused($isTokenFocused)
        .onSubmit(signInWithToken)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)

      Button("Find your app tokens on Micro.blog") {
        openURL(URL(string: "https://micro.blog/account/apps")!)
      }
      .buttonStyle(.link)
      .font(.callout)
      .padding(.top, 12)

      Spacer(minLength: 0)

      Button(action: signInWithToken) {
        HStack(spacing: 8) {
          if session.phase == .verifying {
            ProgressView().controlSize(.small).tint(.white)
          }
          Text(session.phase == .verifying ? "Checking token…" : "Sign In")
        }
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PrimaryCapsuleButtonStyle())
      .keyboardShortcut(.defaultAction)
      .disabled(token.trimmed.isEmpty || session.isBusy)

      errorMessage
        .frame(height: 44)
    }
  }

  @ViewBuilder
  private var errorMessage: some View {
    if let message = session.errorMessage {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
        .transition(.opacity)
    }
  }

  private func animateIn() {
    withAnimation(.spring(duration: 0.55, bounce: 0.22)) {
      isCardShown = true
    }

    withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.2)) {
      isButtonShown = true
    }
  }

  private func showToken() {
    session.errorMessage = nil
    mode = .token
    isTokenFocused = true
  }

  private func showWelcome() {
    session.errorMessage = nil
    token = ""
    mode = .welcome
  }

  private func signInWithMicroBlog() {
    Task {
      await session.signIn { url in
        do {
          return try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: MicroBlogAuth.scheme,
            preferredBrowserSession: .shared
          )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
          throw CancellationError()
        }
      }
    }
  }

  private func signInWithToken() {
    guard !token.trimmed.isEmpty else { return }
    Task { await session.signIn(token: token) }
  }
}

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PrimaryCapsuleButton(configuration: configuration)
  }
}

private struct PrimaryCapsuleButton: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  private var isLifted: Bool { isHovered && isEnabled && !configuration.isPressed }

  var body: some View {
    configuration.label
      .foregroundStyle(.white)
      .padding(.vertical, 15)
      .padding(.horizontal, 20)
      .background {
        Capsule()
          .fill(LinearGradient(
            colors: [Color(hex: 0xFF9A1F), Color(hex: 0xF27200)],
            startPoint: .top,
            endPoint: .bottom
          ))
          .overlay {
            Capsule().strokeBorder(.white.opacity(isLifted ? 0.4 : 0.25), lineWidth: 1)
          }
          .shadow(
            color: Color.accentColor.opacity(isEnabled ? (isLifted ? 0.6 : 0.45) : 0),
            radius: isLifted ? 20 : 14,
            y: isLifted ? 8 : 6
          )
      }
      .opacity(isEnabled ? 1 : 0.55)
      .scaleEffect(configuration.isPressed ? 0.97 : (isLifted ? 1.03 : 1))
      .brightness(configuration.isPressed ? -0.05 : (isLifted ? 0.04 : 0))
      .animation(.spring(duration: 0.25, bounce: 0.3), value: isLifted)
      .animation(.spring(duration: 0.2), value: configuration.isPressed)
      .contentShape(.capsule)
      .onHover { isHovered = $0 }
  }
}

private struct AnimatedWaveform: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { timeline in
      let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

      Canvas { context, size in
        let count = 36
        let spacing: CGFloat = 4
        let width = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let gradient = Gradient(colors: [Color.accentColor, Color.gold])

        for index in 0..<count {
          let position = Double(index) / Double(count - 1)
          let envelope = sin(position * .pi)
          let wave = 0.5 + 0.5 * sin(time * 2.2 + Double(index) * 0.55) * cos(time * 0.9 + Double(index) * 0.21)
          let height = max(4, size.height * CGFloat(0.18 + 0.82 * envelope * wave))
          let rect = CGRect(
            x: CGFloat(index) * (width + spacing),
            y: (size.height - height) / 2,
            width: width,
            height: height
          )

          context.fill(
            Path(roundedRect: rect, cornerRadius: width / 2),
            with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY))
          )
        }
      }
      .opacity(0.45)
    }
    .accessibilityHidden(true)
  }
}
