import AVFoundation
import Observation

@Observable
final class Recorder {
  enum Phase {
    case idle
    case recording
    case paused
  }

  static let minimumSeconds = 1.0
  static let liveHistoryCount = 400
  nonisolated static let framesPerLevel = 2_646
  static let liveSmoothing: Float = 0.4
  nonisolated static let levelInterval = Double(framesPerLevel) / AudioEditing.sampleRate
  static let inputDeviceDefaultsKey = "inputDeviceUID"

  private(set) var phase: Phase = .idle
  private(set) var elapsed: Double = 0
  private(set) var level: Float = 0
  private(set) var liveLevels: [Float] = []
  private(set) var liveEndTime: Double = 0
  private(set) var liveReceivedAt = Date()
  private(set) var owner: UUID?
  var errorMessage: String?

  @ObservationIgnored private var engine: AVAudioEngine?
  @ObservationIgnored private var writer: TapWriter?
  @ObservationIgnored private var levels: [Float] = []
  @ObservationIgnored private var smoothedLevel: Float = 0
  @ObservationIgnored private var activity: NSObjectProtocol?
  @ObservationIgnored private var isStarting = false

  var isActive: Bool { phase != .idle }

  func isOwned(by id: UUID) -> Bool {
    owner == id
  }

  func start(owner id: UUID) async -> Bool {
    guard phase == .idle, !isStarting else { return false }

    isStarting = true
    defer { isStarting = false }
    errorMessage = nil

    guard await AVAudioApplication.requestRecordPermission() else {
      errorMessage = "Wavelength needs microphone access to record. You can allow it in System Settings → Privacy & Security → Microphone."
      return false
    }

    NotificationCenter.default.post(name: .wavelengthWillRecord, object: nil)

    do {
      let engine = AVAudioEngine()
      let input = engine.inputNode

      if let device = InputDevices.device(uid: UserDefaults.standard.string(forKey: Self.inputDeviceDefaultsKey)),
         let unit = input.audioUnit {
        var deviceID = device.id
        AudioUnitSetProperty(
          unit,
          kAudioOutputUnitProperty_CurrentDevice,
          kAudioUnitScope_Global,
          0,
          &deviceID,
          UInt32(MemoryLayout<AudioDeviceID>.size)
        )
      }

      let format = input.outputFormat(forBus: 0)

      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw AudioError(message: "No microphone is available.")
      }

      let writer = try TapWriter(inputFormat: format, output: AppDirectories.scratchFile("recording")) { [weak self] levels, frames, levelFrames in
        Task { @MainActor in
          self?.receive(levels: levels, frames: frames, levelFrames: levelFrames)
        }
      }

      writer.install(on: input)
      engine.prepare()
      try engine.start()

      self.engine = engine
      self.writer = writer
      levels = []
      liveLevels = []
      smoothedLevel = 0
      liveEndTime = 0
      liveReceivedAt = Date()
      elapsed = 0
      level = 0
      owner = id
      phase = .recording
      activity = ProcessInfo.processInfo.beginActivity(
        options: [.idleSystemSleepDisabled, .userInitiated],
        reason: "Recording a Wavelength episode"
      )
      return true
    } catch {
      teardown()
      errorMessage = "Wavelength could not start recording. Check that a microphone is available, then try again."
      return false
    }
  }

  func pause() {
    guard phase == .recording else { return }
    engine?.pause()
    level = 0
    phase = .paused
  }

  func resume() {
    guard phase == .paused, let engine else { return }

    do {
      try engine.start()
      phase = .recording
    } catch {
      errorMessage = "That take could not be resumed. Save it, or discard it and record again."
    }
  }

  func togglePause() {
    if phase == .recording {
      pause()
    } else if phase == .paused {
      resume()
    }
  }

  func finish() -> RecordedTake? {
    guard phase != .idle, let writer else { return nil }

    let duration = writer.duration
    let url = writer.output
    let waveform = Waveform.downsample(levels)
    teardown()

    guard duration >= Self.minimumSeconds else {
      try? FileManager.default.removeItem(at: url)
      errorMessage = "That recording was too short. Hold on a moment longer so there is something to save."
      return nil
    }

    return RecordedTake(url: url, durationSeconds: duration, waveform: waveform)
  }

  func cancel() {
    let url = writer?.output
    teardown()

    if let url {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func receive(levels newLevels: [Float], frames: Int64, levelFrames: Int64) {
    guard phase == .recording else { return }

    elapsed = Double(frames) / AudioEditing.sampleRate

    guard !newLevels.isEmpty else { return }

    levels += newLevels

    for raw in newLevels {
      smoothedLevel += (raw - smoothedLevel) * Self.liveSmoothing
      liveLevels.append(smoothedLevel)
    }

    level = smoothedLevel
    liveEndTime = Double(levelFrames) / AudioEditing.sampleRate
    liveReceivedAt = Date()

    if liveLevels.count > Self.liveHistoryCount {
      liveLevels.removeFirst(liveLevels.count - Self.liveHistoryCount)
    }
  }

  private func teardown() {
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    writer?.close()
    engine = nil
    writer = nil
    phase = .idle
    owner = nil
    level = 0

    if let activity {
      ProcessInfo.processInfo.endActivity(activity)
      self.activity = nil
    }
  }
}

private nonisolated final class TapWriter: @unchecked Sendable {
  let output: URL

  private var file: AVAudioFile?
  private let converter: AVAudioConverter
  private let monoFormat: AVAudioFormat
  private let stereoFormat: AVAudioFormat
  private let onLevels: @Sendable ([Float], Int64, Int64) -> Void
  private let lock = NSLock()
  private var framesWritten: Int64 = 0
  private var chunkSum: Float = 0
  private var chunkCount = 0
  private var levelFrames: Int64 = 0

  init(inputFormat: AVAudioFormat, output: URL, onLevels: @escaping @Sendable ([Float], Int64, Int64) -> Void) throws {
    guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioEditing.sampleRate, channels: 1, interleaved: false),
          let stereo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioEditing.sampleRate, channels: 2, interleaved: false),
          let converter = AVAudioConverter(from: inputFormat, to: mono) else {
      throw AudioError(message: "The microphone format is not supported.")
    }

    converter.downmix = true
    self.output = output
    self.monoFormat = mono
    self.stereoFormat = stereo
    self.converter = converter
    self.onLevels = onLevels
    self.file = try AVAudioFile(
      forWriting: output,
      settings: AudioEditing.canonicalSettings,
      commonFormat: .pcmFormatFloat32,
      interleaved: false
    )
  }

  var duration: Double {
    lock.withLock { Double(framesWritten) / AudioEditing.sampleRate }
  }

  func install(on node: AVAudioInputNode) {
    node.installTap(onBus: 0, bufferSize: 2_048, format: node.outputFormat(forBus: 0)) { [self] buffer, _ in
      process(buffer)
    }
  }

  func close() {
    lock.withLock { file = nil }
  }

  private func process(_ buffer: AVAudioPCMBuffer) {
    let ratio = AudioEditing.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)

    guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: capacity) else { return }

    let feed = BufferFeed(buffer)
    var error: NSError?
    converter.convert(to: mono, error: &error) { _, status in
      feed.next(status)
    }

    guard error == nil, mono.frameLength > 0,
          let stereo = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: mono.frameLength),
          let source = mono.floatChannelData?[0],
          let left = stereo.floatChannelData?[0],
          let right = stereo.floatChannelData?[1] else {
      return
    }

    let count = Int(mono.frameLength)
    var levels: [Float] = []

    for index in 0..<count {
      let sample = source[index]
      left[index] = sample
      right[index] = sample
      chunkSum += sample * sample
      chunkCount += 1

      if chunkCount == Recorder.framesPerLevel {
        levels.append(Waveform.normalize(rms: (chunkSum / Float(chunkCount)).squareRoot()))
        levelFrames += Int64(chunkCount)
        chunkSum = 0
        chunkCount = 0
      }
    }

    stereo.frameLength = mono.frameLength

    let frames: Int64? = lock.withLock {
      guard let file else { return nil }

      do {
        try file.write(from: stereo)
        framesWritten += Int64(count)
        return framesWritten
      } catch {
        return nil
      }
    }

    if let frames {
      onLevels(levels, frames, levelFrames)
    }
  }
}

private nonisolated final class BufferFeed: @unchecked Sendable {
  private var buffer: AVAudioPCMBuffer?

  init(_ buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    guard let buffer else {
      status.pointee = .noDataNow
      return nil
    }

    self.buffer = nil
    status.pointee = .haveData
    return buffer
  }
}

extension Notification.Name {
  static let wavelengthWillRecord = Notification.Name("WavelengthWillRecord")
  static let wavelengthWillPlay = Notification.Name("WavelengthWillPlay")
}
