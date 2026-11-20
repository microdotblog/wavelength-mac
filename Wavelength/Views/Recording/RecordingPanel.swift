import SwiftUI

enum RecordingPanelStyle {
  case compact
  case bar
  case card(title: String?)
}

struct RecordingPanel<Accessory: View>: View {
  var idleTitle: String
  var style: RecordingPanelStyle
  var autoStart: Bool
  var focusTitle: String?
  let onFinish: (RecordedTake) async throws -> Void
  var onCancel: (() -> Void)?
  let accessory: Accessory

  @Environment(Recorder.self) private var recorder
  @Environment(AppModel.self) private var model
  @Environment(Toasts.self) private var toasts
  @State private var owner = UUID()
  @State private var isConfirmingCancel = false
  @State private var isSaving = false
  @State private var isPresent = false
  @State private var notice: String?
  @State private var isStartingFromCard = false

  private var isMine: Bool { recorder.isOwned(by: owner) }

  init(
    idleTitle: String = "Record",
    style: RecordingPanelStyle = .compact,
    autoStart: Bool = false,
    focusTitle: String? = nil,
    onFinish: @escaping (RecordedTake) async throws -> Void,
    onCancel: (() -> Void)? = nil,
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.idleTitle = idleTitle
    self.style = style
    self.autoStart = autoStart
    self.focusTitle = focusTitle
    self.onFinish = onFinish
    self.onCancel = onCancel
    self.accessory = accessory()
  }

  var body: some View {
    Group {
      switch style {
      case .compact: compact
      case .bar: bar
      case .card(let title): card(title)
      }
    }
    .focusedSceneValue(\.recordingActions, isMine ? RecordingActions(togglePause: { recorder.togglePause() }, finish: { finish() }) : nil)
    .focusedSceneValue(\.startRecording, canStart ? StartRecordingAction { Task { await start() } } : nil)
    .confirmationDialog("Discard this recording?", isPresented: $isConfirmingCancel) {
      Button("Discard Recording", role: .destructive, action: cancel)
      Button("Keep Recording", role: .cancel) {}
    } message: {
      Text("This removes the current take without saving it.")
    }
    .task {
      if autoStart, !recorder.isActive {
        await start()
      }
    }
    .onAppear { isPresent = true }
    .onDisappear {
      isPresent = false

      if isMine {
        finish()
      }
    }
  }

  private var compact: some View {
    HStack(spacing: 12) {
      if isMine {
        liveStrip
      } else {
        recordButton

        InputDeviceMenu()

        Spacer()

        if recorder.isActive {
          Text("Recording elsewhere…")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var bar: some View {
    HStack(spacing: 12) {
      if isMine {
        liveStrip
      } else {
        recordButton
        InputDeviceMenu()
        accessory
      }
    }
    .frame(minHeight: 32)
  }

  private var liveStrip: some View {
    HStack(spacing: 12) {
      RecordingDot(isPaused: recorder.phase == .paused)
      Text(Formatting.duration(recorder.elapsed))
        .font(.body.monospacedDigit().weight(.semibold))
        .frame(minWidth: 44, alignment: .leading)
      liveWaveform(barWidth: 3, spacing: 2)
        .frame(height: 28)
      pauseButton
      Button("Cancel", role: .destructive) {
        isConfirmingCancel = true
      }
      .help("Cancel recording")
      Button("Done", action: finish)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Finish recording (⌘↩)")
    }
  }

  private var recordButton: some View {
    Button {
      Task { await start() }
    } label: {
      Label(idleTitle, systemImage: "record.circle")
        .labelStyle(.titleAndIcon)
    }
    .buttonStyle(.borderless)
    .tint(Color.accentColor)
    .disabled(!canStart)
    .help("\(idleTitle) (⌘R)")
  }

  private var canStart: Bool {
    !recorder.isActive && !isSaving
  }

  private func card(_ title: String?) -> some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          RecordingDot(isPaused: !isMine || recorder.phase == .paused)
          Text(cardStatus)
            .font(.caption.weight(.heavy))
            .tracking(2)
            .foregroundStyle(isMine && recorder.phase == .recording ? Color.accentColor : Color.secondary)
          Text(cardHint)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let title {
          Text(title)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
        }

        if let notice {
          Label(notice, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.top, 22)

      Spacer(minLength: 0)

      Text(isMine ? Formatting.duration(recorder.elapsed) : "0:00")
        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(isMine && recorder.phase == .recording ? .primary : .secondary)
        .contentTransition(.numericText())
        .padding(.bottom, 18)

      liveWaveform(barWidth: 4, spacing: 3)
        .frame(height: 84)
        .mask(LinearGradient(colors: [.clear, .black, .black, .black], startPoint: .leading, endPoint: .trailing))
        .padding(.horizontal, 28)
        .padding(.bottom, 8)

      Button {
        if isMine {
          recorder.togglePause()
        } else {
          isStartingFromCard = true

          Task {
            await start()
            isStartingFromCard = false
          }
        }
      } label: {
        RecordButtonFace(phase: cardFacePhase, level: isMine ? recorder.level : 0)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.space, modifiers: [])
      .disabled(isSaving || (recorder.isActive && !isMine))
      .help(isMine ? (recorder.phase == .paused ? "Resume (Space)" : "Pause (Space)") : "Start recording (Space)")

      HStack(spacing: 12) {
        if title == nil || !isMine {
          InputDeviceMenu()
            .disabled(recorder.isActive || isSaving)
        }

        Spacer()

        Button(role: .cancel) {
          if isMine {
            isConfirmingCancel = true
          } else {
            onCancel?()
          }
        } label: {
          Text("Cancel")
            .frame(width: 56)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(.cancelAction)
        .disabled(isSaving)

        Button(action: finish) {
          Text("Save")
            .frame(width: 56)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!isMine || isSaving)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 20)
    }
    .task(id: notice) {
      guard notice != nil else { return }
      try? await Task.sleep(for: .seconds(4))
      notice = nil
    }
  }

  private var cardFacePhase: Recorder.Phase {
    if isMine {
      recorder.phase
    } else if isStartingFromCard {
      .recording
    } else {
      .idle
    }
  }

  private var cardStatus: String {
    switch isMine ? recorder.phase : .idle {
    case .idle: "READY"
    case .recording: "RECORDING"
    case .paused: "PAUSED"
    }
  }

  private var cardHint: String {
    switch isMine ? recorder.phase : .idle {
    case .idle: "Space to start recording"
    case .recording: "Space to pause"
    case .paused: "Space to resume"
    }
  }

  private func liveWaveform(barWidth: CGFloat, spacing: CGFloat) -> some View {
    LiveWaveformView(
      levels: isMine ? recorder.liveLevels : [],
      endTime: recorder.liveEndTime,
      receivedAt: recorder.liveReceivedAt,
      isRunning: isMine && recorder.phase == .recording,
      barWidth: barWidth,
      spacing: spacing
    )
  }

  private var pauseButton: some View {
    Button {
      recorder.togglePause()
    } label: {
      Image(systemName: recorder.phase == .paused ? "record.circle" : "pause.fill")
    }
    .buttonStyle(.borderless)
    .help(recorder.phase == .paused ? "Resume (⇧⌘R)" : "Pause (⇧⌘R)")
  }

  private func start() async {
    if let focusTitle, !isCard {
      model.presentRecording(title: focusTitle, autoStart: true, onFinish: onFinish)
      return
    }

    notice = nil
    let didStart = await recorder.start(owner: owner)

    if didStart, !isPresent {
      recorder.cancel()
    } else if !didStart, let message = recorder.errorMessage {
      show(message)
    }
  }

  private var isCard: Bool {
    if case .card = style { true } else { false }
  }

  private func finish() {
    guard isMine, let take = recorder.finish() else {
      if let message = recorder.errorMessage {
        show(message)
        recorder.errorMessage = nil
      }
      return
    }

    isSaving = true

    Task {
      do {
        try await onFinish(take)
      } catch {
        try? FileManager.default.removeItem(at: take.url)
        show(error.localizedDescription)
      }

      isSaving = false
    }
  }

  private func show(_ message: String) {
    if isCard {
      notice = message
    } else {
      toasts.show(message)
    }
  }

  private func cancel() {
    recorder.cancel()
    onCancel?()
  }
}

struct RecordButtonFace: View {
  let phase: Recorder.Phase
  let level: Float

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var layoutFrame = CGRect.zero
  @State private var hasSettled = false

  private var canAnimate: Bool { hasSettled && !reduceMotion }

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.accentColor, lineWidth: 3)
        .frame(width: 120, height: 120)
        .scaleEffect(1 + CGFloat(level) * 0.35)
        .opacity(phase == .recording ? Double(level) * 0.7 : 0)
        .animation(canAnimate ? .easeOut(duration: 0.12) : nil, value: level)

      Circle()
        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        .overlay {
          Circle().strokeBorder(Color.accentColor, lineWidth: 2)
        }
        .overlay {
          icon
        }
        .frame(width: 120, height: 120)
        .phaseAnimator(canAnimate ? [1.0, 1.035] : [1.0]) { face, scale in
          face.scaleEffect(phase == .idle && canAnimate ? scale : 1)
        } animation: { _ in
          .easeInOut(duration: 1.6)
        }
    }
    .frame(width: 160, height: 160)
    .contentShape(.circle)
    .transaction { transaction in
      if !canAnimate {
        transaction.animation = nil
        transaction.disablesAnimations = true
      }
    }
    .onGeometryChange(for: CGRect.self) { geometry in
      geometry.frame(in: .global)
    } action: { frame in
      hasSettled = false
      layoutFrame = frame
    }
    .task(id: layoutFrame) {
      guard !layoutFrame.isEmpty else { return }

      // Let the sheet appear and restart the wait whenever layout moves the button.
      do {
        try await Task.sleep(for: .milliseconds(500))
      } catch {
        return
      }
      hasSettled = true
    }
    .onDisappear { hasSettled = false }
  }

  private var icon: some View {
    RecordGlyph(progress: phase == .recording ? 1 : 0)
      .fill(Color.accentColor)
      .frame(width: 120, height: 120)
      .animation(canAnimate ? .spring(duration: 0.25, bounce: 0.2) : nil, value: phase)
  }
}

nonisolated private struct RecordGlyph: Shape {
  var progress: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  private struct Piece {
    var rect: CGRect
    var leading: CGFloat
    var trailing: CGFloat
  }

  private static let dot = [
    Piece(rect: CGRect(x: 0.317, y: 0.317, width: 0.183, height: 0.366), leading: 0.183, trailing: 0),
    Piece(rect: CGRect(x: 0.5, y: 0.317, width: 0.183, height: 0.366), leading: 0, trailing: 0.183),
  ]

  private static let pause = [
    Piece(rect: CGRect(x: 0.346, y: 0.317, width: 0.117, height: 0.366), leading: 0.033, trailing: 0.033),
    Piece(rect: CGRect(x: 0.537, y: 0.317, width: 0.117, height: 0.366), leading: 0.033, trailing: 0.033),
  ]

  func path(in rect: CGRect) -> Path {
    var path = Path()

    for (from, to) in zip(Self.dot, Self.pause) {
      let unit = CGRect(
        x: mix(from.rect.minX, to.rect.minX),
        y: mix(from.rect.minY, to.rect.minY),
        width: mix(from.rect.width, to.rect.width),
        height: mix(from.rect.height, to.rect.height)
      )
      let frame = CGRect(
        x: rect.minX + unit.minX * rect.width,
        y: rect.minY + unit.minY * rect.height,
        width: unit.width * rect.width,
        height: unit.height * rect.height
      )
      let leading = mix(from.leading, to.leading) * rect.width
      let trailing = mix(from.trailing, to.trailing) * rect.width

      path.addRoundedRect(
        in: frame,
        cornerRadii: RectangleCornerRadii(
          topLeading: leading,
          bottomLeading: leading,
          bottomTrailing: trailing,
          topTrailing: trailing
        )
      )
    }

    return path
  }

  private func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
    from + (to - from) * progress
  }
}

struct RecordingDot: View {
  let isPaused: Bool

  var body: some View {
    Circle()
      .fill(isPaused ? Color.secondary : Color.accentColor)
      .frame(width: 10, height: 10)
      .phaseAnimator([1.0, 0.35]) { dot, opacity in
        dot.opacity(isPaused ? 1 : opacity)
      } animation: { _ in
        .easeInOut(duration: 0.8)
      }
  }
}

struct InputDeviceMenu: View {
  @AppStorage(Recorder.inputDeviceDefaultsKey) private var deviceUID = ""
  @State private var devices: [InputDevice] = []

  var body: some View {
    Menu {
      Picker("Microphone", selection: $deviceUID) {
        Text(defaultLabel).tag("")
        Divider()
        ForEach(devices) { device in
          Text(device.name).tag(device.uid)
        }
      }
      .pickerStyle(.inline)
    } label: {
      Label(currentName, systemImage: "mic")
    }
    .menuStyle(.button)
    .buttonStyle(.borderless)
    .fixedSize()
    .onAppear { devices = InputDevices.all() }
  }

  private var defaultLabel: String {
    if let name = InputDevices.defaultName {
      "System Default (\(name))"
    } else {
      "System Default"
    }
  }

  private var currentName: String {
    if devices.isEmpty {
      return "No Microphone"
    }

    return devices.first { $0.uid == deviceUID }?.name ?? InputDevices.defaultName ?? "Microphone"
  }
}

struct StartRecordingAction {
  let start: () -> Void
}

struct RecordingActions {
  let togglePause: () -> Void
  let finish: () -> Void
}

extension RecordingPanel where Accessory == EmptyView {
  init(
    idleTitle: String = "Record",
    style: RecordingPanelStyle = .compact,
    autoStart: Bool = false,
    focusTitle: String? = nil,
    onFinish: @escaping (RecordedTake) async throws -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.init(idleTitle: idleTitle, style: style, autoStart: autoStart, focusTitle: focusTitle, onFinish: onFinish, onCancel: onCancel) {
      EmptyView()
    }
  }
}

extension FocusedValues {
  @Entry var recordingActions: RecordingActions?
  @Entry var startRecording: StartRecordingAction?
}
