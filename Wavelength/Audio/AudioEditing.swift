import AVFoundation

nonisolated struct AudioError: LocalizedError, Sendable {
  let message: String
  var errorDescription: String? { message }

  static let missingAudio = AudioError(message: "That file does not contain any audio.")
}

nonisolated struct ProcessedAudio: Sendable {
  let url: URL
  let durationSeconds: Double
  let waveform: [Float]
}

nonisolated enum AudioEditing {
  static let sampleRate: Double = 44_100
  static let channelCount = 2
  static let bitRate = 128_000

  static var canonicalSettings: [String: any Sendable] {
    [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channelCount,
      AVEncoderBitRateKey: bitRate,
    ]
  }

  @concurrent static func duration(of url: URL) async throws -> Double {
    let seconds = try await AVURLAsset(url: url).load(.duration).seconds
    return seconds.isFinite ? max(seconds, 0) : 0
  }

  @concurrent static func normalize(_ source: URL) async throws -> ProcessedAudio {
    let output = AppDirectories.scratchFile("import")

    do {
      try await transcode(AVURLAsset(url: source), to: output)
      let duration = try await duration(of: output)

      guard duration > 0 else {
        throw AudioError.missingAudio
      }

      let waveform = (try? await WaveformAnalyzer.levels(of: output)) ?? []
      return ProcessedAudio(url: output, durationSeconds: duration, waveform: waveform)
    } catch {
      try? FileManager.default.removeItem(at: output)
      throw error
    }
  }

  @concurrent static func split(_ source: URL, at seconds: Double, waveform: [Float]) async throws -> (ProcessedAudio, ProcessedAudio) {
    let total = try await duration(of: source)

    guard seconds > 0.05, seconds < total - 0.05 else {
      throw AudioError(message: "Move the playhead inside the segment to split it.")
    }

    let pieces = try await pieces(of: source, keeping: [0..<seconds, seconds..<total], waveform: waveform)
    return (pieces[0], pieces[1])
  }

  @concurrent static func pieces(of source: URL, keeping ranges: [Range<Double>], waveform: [Float]) async throws -> [ProcessedAudio] {
    let asset = AVURLAsset(url: source)
    let total = try await duration(of: source)
    var made: [URL] = []

    do {
      var pieces: [ProcessedAudio] = []

      for range in ranges {
        let start = min(max(range.lowerBound, 0), total)
        let end = min(max(range.upperBound, start), total)
        let output = AppDirectories.scratchFile("split")
        made.append(output)

        try await extract(
          asset,
          range: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 44_100), end: CMTime(seconds: end, preferredTimescale: 44_100)),
          to: output
        )

        pieces.append(ProcessedAudio(
          url: output,
          durationSeconds: try await duration(of: output),
          waveform: Waveform.slice(waveform, from: start / total, to: end / total)
        ))
      }

      return pieces
    } catch {
      made.forEach { try? FileManager.default.removeItem(at: $0) }
      throw error
    }
  }

  @concurrent static func merge(_ sources: [URL], to output: URL) async throws {
    guard !sources.isEmpty else {
      throw AudioError(message: "This recording has no segments to merge.")
    }

    let composition = try await composition(of: sources)
    try? FileManager.default.removeItem(at: output)

    if try await sharesOneFormat(sources) {
      do {
        try await export(composition, preset: AVAssetExportPresetPassthrough, range: nil, to: output)
        return
      } catch {
        try? FileManager.default.removeItem(at: output)
      }
    }

    try await transcode(composition, to: output)
  }

  static func composition(of sources: [URL]) async throws -> AVMutableComposition {
    let composition = AVMutableComposition()

    guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw AudioError(message: "The recording could not be prepared.")
    }

    var cursor = CMTime.zero

    for source in sources {
      let asset = AVURLAsset(url: source)

      guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw AudioError(message: "One of the segments is missing its audio.")
      }

      let range = try await sourceTrack.load(.timeRange)
      try track.insertTimeRange(range, of: sourceTrack, at: cursor)
      cursor = cursor + range.duration
    }

    return composition
  }

  static func transcode(_ asset: AVAsset, to output: URL, range: CMTimeRange? = nil) async throws {
    let tracks = try await asset.loadTracks(withMediaType: .audio)

    guard !tracks.isEmpty else {
      throw AudioError.missingAudio
    }

    try? FileManager.default.removeItem(at: output)

    let reader = try AVAssetReader(asset: asset)

    if let range {
      reader.timeRange = range
    }

    let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channelCount,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    readerOutput.alwaysCopiesSampleData = false

    guard reader.canAdd(readerOutput) else {
      throw AudioError(message: "That audio file could not be read.")
    }

    reader.add(readerOutput)

    let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: canonicalSettings)
    writerInput.expectsMediaDataInRealTime = false

    guard writer.canAdd(writerInput) else {
      throw AudioError(message: "That audio file could not be converted.")
    }

    writer.add(writerInput)

    guard reader.startReading(), writer.startWriting() else {
      throw reader.error ?? writer.error ?? AudioError(message: "That audio file could not be converted.")
    }

    writer.startSession(atSourceTime: range?.start ?? .zero)

    let pump = SamplePump(reader: reader, output: readerOutput, writer: writer, input: writerInput)
    try await pump.run()
  }

  private static func extract(_ asset: AVAsset, range: CMTimeRange, to output: URL) async throws {
    do {
      try await export(asset, preset: AVAssetExportPresetPassthrough, range: range, to: output)
    } catch {
      try? FileManager.default.removeItem(at: output)
      try await transcode(asset, to: output, range: range)
    }
  }

  private static func export(_ asset: AVAsset, preset: String, range: CMTimeRange?, to output: URL) async throws {
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw AudioError(message: "The audio could not be exported.")
    }

    if let range {
      session.timeRange = range
    }

    try await session.export(to: output, as: .m4a)
  }

  private static func sharesOneFormat(_ sources: [URL]) async throws -> Bool {
    var signature: String?

    for source in sources {
      guard let track = try await AVURLAsset(url: source).loadTracks(withMediaType: .audio).first,
            let description = try await track.load(.formatDescriptions).first,
            let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
        return false
      }

      let current = "\(basic.mFormatID)-\(basic.mSampleRate)-\(basic.mChannelsPerFrame)"

      if let signature, signature != current {
        return false
      }

      signature = current
    }

    return true
  }
}

private nonisolated final class SamplePump: @unchecked Sendable {
  private let reader: AVAssetReader
  private let output: AVAssetReaderOutput
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let queue = DispatchQueue(label: "blog.micro.wavelength.transcode")

  init(reader: AVAssetReader, output: AVAssetReaderOutput, writer: AVAssetWriter, input: AVAssetWriterInput) {
    self.reader = reader
    self.output = output
    self.writer = writer
    self.input = input
  }

  func run() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      input.requestMediaDataWhenReady(on: queue) { [self] in
        while input.isReadyForMoreMediaData {
          if let buffer = output.copyNextSampleBuffer() {
            if !input.append(buffer) {
              reader.cancelReading()
              input.markAsFinished()
              continuation.resume(throwing: writer.error ?? AudioError(message: "The audio could not be written."))
              return
            }
          } else {
            input.markAsFinished()

            if reader.status == .failed {
              writer.cancelWriting()
              continuation.resume(throwing: reader.error ?? AudioError(message: "The audio could not be read."))
            } else {
              writer.finishWriting { [self] in
                if writer.status == .completed {
                  continuation.resume()
                } else {
                  continuation.resume(throwing: writer.error ?? AudioError(message: "The audio could not be written."))
                }
              }
            }

            return
          }
        }
      }
    }
  }
}
