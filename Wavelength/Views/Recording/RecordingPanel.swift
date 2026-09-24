import SwiftUI

struct RecordingPanel: View {
  enum Style {
    case compact
    case hero
  }

  var idleTitle = "Record Segment"
  var style: Style = .compact
  var autoStart = false
  let onFinish: (RecordedTake) async throws -> Void
  var onCancel: (() -> Void)?

  @Environment(Recorder.self) private var recorder
  @Environment(Toasts.self) private var toasts
  @State private var owner = UUID()
  @State private var isConfirmingCancel = false
  @State private var isSaving = false

  private var isMine: Bool { recorder.isOwned(by: owner) }

  var body: some View {
    Group {
      switch style {
      case .compact: compact
      case .hero: hero
      }
    }
    .focusedSceneValue(\.recordingActions, isMine ? RecordingActions(togglePause: { recorder.togglePause() }, finish: { finish() }) : nil)
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
    .onDisappear {
      if isMine {
        finish()
      }
    }
  }

  private var compact: some View {
    HStack(spacing: 12) {
      if isMine {
        RecordingDot(isPaused: recorder.phase == .paused)
        Text(Formatting.duration(recorder.elapsed))
          .font(.title3.monospacedDigit().weight(.semibold))
          .frame(minWidth: 52, alignment: .leading)
        LiveWaveformView(levels: recorder.liveLevels)
          .frame(height: 34)
        pauseButton
        Button("Done", action: finish)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: [.command])
        Button {
          isConfirmingCancel = true
        } label: {
          Image(systemName: "xmark")
        }
        .help("Discard recording")
      } else {
        Button {
          Task { await start() }
        } label: {
          Label(idleTitle, systemImage: "record.circle")
        }
        .disabled(recorder.isActive || isSaving)

        InputDeviceMenu()

        Spacer()

        if recorder.isActive {
          Text("Recording elsewhere…")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .card()
  }

  private var hero: some View {
    VStack(spacing: 28) {
      Text(isMine ? Formatting.duration(recorder.elapsed) : "0:00")
        .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(isMine ? Color.ink : Color.inkSoft)
        .contentTransition(.numericText())

      LiveWaveformView(levels: isMine ? recorder.liveLevels : [], barWidth: 4, spacing: 3)
        .frame(height: 96)
        .frame(maxWidth: 640)

      HStack(spacing: 28) {
        if isMine {
          Button {
            isConfirmingCancel = true
          } label: {
            Image(systemName: "xmark")
              .font(.title2.weight(.semibold))
              .frame(width: 52, height: 52)
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: .circle)
          .help("Discard recording")
        }

        Button {
          if isMine {
            recorder.togglePause()
          } else {
            Task { await start() }
          }
        } label: {
          RecordButtonFace(phase: isMine ? recorder.phase : .idle)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(isSaving || (recorder.isActive && !isMine))
        .help(isMine ? (recorder.phase == .paused ? "Resume" : "Pause") : "Start recording")

        if isMine {
          Button(action: finish) {
            Image(systemName: "checkmark")
              .font(.title2.weight(.bold))
              .foregroundStyle(.white)
              .frame(width: 52, height: 52)
              .background(Color.accentColor, in: .circle)
          }
          .buttonStyle(.plain)
          .keyboardShortcut(.return, modifiers: [.command])
          .help("Finish and save")
        }
      }

      HStack(spacing: 6) {
        Text(heroHint)
          .foregroundStyle(.secondary)
        if !isMine {
          InputDeviceMenu()
            .fixedSize()
        }
      }
      .font(.callout)
    }
  }

  private var heroHint: String {
    switch isMine ? recorder.phase : .idle {
    case .idle: "Press Space to start recording."
    case .recording: "Recording… press Space to pause."
    case .paused: "Paused. Press Space to resume, or ⌘↩ to save."
    }
  }

  private var pauseButton: some View {
    Button {
      recorder.togglePause()
    } label: {
      Image(systemName: recorder.phase == .paused ? "record.circle" : "pause.fill")
    }
    .help(recorder.phase == .paused ? "Resume" : "Pause")
  }

  private func start() async {
    if !(await recorder.start(owner: owner)), let message = recorder.errorMessage {
      toasts.show(message)
    }
  }

  private func finish() {
    guard isMine, let take = recorder.finish() else {
      if let message = recorder.errorMessage {
        toasts.show(message)
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
        toasts.show(error.localizedDescription)
      }

      isSaving = false
    }
  }

  private func cancel() {
    recorder.cancel()
    onCancel?()
  }
}

private struct RecordButtonFace: View {
  let phase: Recorder.Phase

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(Color.recording.opacity(0.35), lineWidth: 5)
        .frame(width: 96, height: 96)

      if phase == .recording {
        Image(systemName: "pause.fill")
          .font(.system(size: 32, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 80, height: 80)
          .background(Color.recording, in: .circle)
      } else {
        Circle()
          .fill(Color.recording)
          .frame(width: 80, height: 80)
      }
    }
    .contentShape(.circle)
    .symbolEffect(.pulse, isActive: phase == .recording)
  }
}

private struct RecordingDot: View {
  let isPaused: Bool

  var body: some View {
    Circle()
      .fill(isPaused ? Color.inkSoft : Color.recording)
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

struct RecordingActions {
  let togglePause: () -> Void
  let finish: () -> Void
}

extension FocusedValues {
  @Entry var recordingActions: RecordingActions?
}
