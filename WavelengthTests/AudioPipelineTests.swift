import AVFoundation
import Foundation
import Testing
@testable import Wavelength

final class AudioPipelineTests {
  private var created: [URL] = []

  deinit {
    created.forEach { try? FileManager.default.removeItem(at: $0) }
  }

  private func makeTone(seconds: Double, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 1, extension ext: String = "wav") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(UUID().uuidString).\(ext)")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(seconds * sampleRate)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames

    for channel in 0..<Int(channels) {
      let samples = try #require(buffer.floatChannelData?[channel])

      for frame in 0..<Int(frames) {
        samples[frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / Float(sampleRate))
      }
    }

    try file.write(from: buffer)
    created.append(url)
    return url
  }

  private func audioFormat(of url: URL) async throws -> AudioStreamBasicDescription {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
    let description = try #require(try await track.load(.formatDescriptions).first)
    return try #require(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee)
  }

  private func samples(of url: URL) throws -> Data {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let audio = buffer.audioBufferList.pointee.mBuffers
    return Data(bytes: try #require(audio.mData), count: Int(audio.mDataByteSize))
  }

  @Test func importsAnyAudioAsCanonicalStereoALAC() async throws {
    let processed = try await AudioEditing.normalize(makeTone(seconds: 2))
    created.append(processed.url)
    let basic = try await audioFormat(of: processed.url)

    #expect(abs(processed.durationSeconds - 2) < 0.1)
    #expect(basic.mFormatID == kAudioFormatAppleLossless)
    #expect(basic.mFormatFlags == kAppleLosslessFormatFlag_16BitSourceData)
    #expect(basic.mSampleRate == 44_100)
    #expect(basic.mChannelsPerFrame == 2)
    #expect(processed.waveform.count == Waveform.sampleCount)
    #expect(processed.waveform.allSatisfy { $0 > 0.5 })
  }

  @Test func splitsAndRejoinsALACWithoutChangingSamples() async throws {
    let processed = try await AudioEditing.normalize(makeTone(seconds: 3))
    created.append(processed.url)
    let splitTime = 0.653
    let (first, second) = try await AudioEditing.split(processed.url, at: splitTime, waveform: processed.waveform)
    let rejoined = AppDirectories.scratchFile("rejoined")
    created.append(contentsOf: [first.url, second.url, rejoined])

    #expect(abs(first.durationSeconds - splitTime) < 1 / 44_100)
    #expect(abs(second.durationSeconds - (processed.durationSeconds - splitTime)) < 1 / 44_100)
    #expect(!first.waveform.isEmpty)

    try await AudioEditing.merge([first.url, second.url], to: rejoined)
    #expect(try await audioFormat(of: rejoined).mFormatID == kAudioFormatAppleLossless)
    #expect(try samples(of: rejoined) == samples(of: processed.url))
  }

  @Test func refusesToSplitAtTheEdges() async throws {
    let processed = try await AudioEditing.normalize(makeTone(seconds: 1))

    await #expect(throws: AudioError.self) {
      _ = try await AudioEditing.split(processed.url, at: 0.01, waveform: [])
    }
  }

  @Test func mergesLegacyAACAndALACSegmentsInOrder() async throws {
    let first = try await AudioEditing.narrationUploadAudio(from: makeTone(seconds: 1))
    created.append(first)
    let second = try await AudioEditing.normalize(makeTone(seconds: 2, sampleRate: 22_050, channels: 2))
    let output = AppDirectories.scratchFile("merged")
    created.append(contentsOf: [second.url, output])

    try await AudioEditing.merge([first, second.url], to: output)

    #expect(abs(try await AudioEditing.duration(of: output) - 3) < 0.15)
    #expect(try await audioFormat(of: output).mFormatID == kAudioFormatAppleLossless)
    let losslessSamples = try samples(of: second.url)
    #expect(try samples(of: output).suffix(losslessSamples.count) == losslessSamples)
  }

  @Test func preparesAACUploadsWithoutChangingTheLosslessNarration() async throws {
    let source = try await AudioEditing.normalize(makeTone(seconds: 2))
    created.append(source.url)
    let upload = try await AudioEditing.narrationUploadAudio(from: source.url)
    created.append(upload)

    #expect(upload != source.url)
    #expect(upload.pathExtension == "m4a")
    #expect(try await audioFormat(of: source.url).mFormatID == kAudioFormatAppleLossless)
    #expect(try await audioFormat(of: upload).mFormatID == kAudioFormatMPEG4AAC)
    #expect(abs(try await AudioEditing.duration(of: upload) - source.durationSeconds) < 0.1)
    #expect(try await AudioEditing.narrationUploadAudio(from: upload) == upload)
  }

  @Test func encodesMonoMP3() async throws {
    let processed = try await AudioEditing.normalize(makeTone(seconds: 2))
    let output = AppDirectories.scratchFile("episode", extension: "mp3")

    try await MP3Encoder.encode(processed.url, to: output)

    let basic = try await audioFormat(of: output)

    #expect(basic.mFormatID == kAudioFormatMPEGLayer3)
    #expect(basic.mChannelsPerFrame == 1)
    #expect(abs(try await AudioEditing.duration(of: output) - 2) < 0.15)
  }
}

@MainActor
final class EditingFlowTests {
  let root = FileManager.default.temporaryDirectory.appending(path: "wavelength-flow-\(UUID().uuidString)")

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  private func take(seconds: Double) async throws -> RecordedTake {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let url = FileManager.default.temporaryDirectory.appending(path: "flow-\(UUID().uuidString).wav")
    let frames = AVAudioFrameCount(seconds * 44_100)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames

    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }

    let processed = try await AudioEditing.normalize(url)
    try? FileManager.default.removeItem(at: url)
    return RecordedTake(url: processed.url, durationSeconds: processed.durationSeconds, waveform: processed.waveform)
  }

  @Test func splittingAnEpisodeReplacesTheSegmentAndRemergesAudio() async throws {
    let session = Session()
    let library = Library(storage: EpisodeStorage(root: root.appending(path: "episodes")), session: session, posts: PostsStore(session: session))
    let episode = try library.create(from: try await take(seconds: 3))
    let mergedBefore = try await library.mergedAudio(episode.id)
    #expect(abs(try await AudioEditing.duration(of: mergedBefore) - 3) < 0.15)

    try library.append(try await take(seconds: 1), to: episode.id)
    try await library.split(episode.id, clip: try #require(library.episode(episode.id)?.clips.first), at: 1)

    let clips = try #require(library.episode(episode.id)?.clips)
    #expect(clips.map(\.name) == ["segment-3.m4a", "segment-4.m4a", "segment-2.m4a"])
    #expect(!FileManager.default.fileExists(atPath: episode.folder.appending(path: "segment-1.m4a").path))

    let mergedAfter = try await library.mergedAudio(episode.id)
    #expect(abs(try await AudioEditing.duration(of: mergedAfter) - 4) < 0.2)
  }

  @Test func deletingARangeAcrossSegmentsKeepsTheRest() async throws {
    let session = Session()
    let library = Library(storage: EpisodeStorage(root: root.appending(path: "episodes")), session: session, posts: PostsStore(session: session))
    let episode = try library.create(from: try await take(seconds: 3))
    try library.append(try await take(seconds: 2), to: episode.id)

    let clips = try #require(library.episode(episode.id)?.clips)
    let spans = [
      SegmentCarving.Span(name: clips[0].name, start: 0, duration: clips[0].durationSeconds),
      SegmentCarving.Span(name: clips[1].name, start: clips[0].durationSeconds, duration: clips[1].durationSeconds),
    ]
    try await library.carve(episode.id, keeping: SegmentCarving.plan(.delete, range: 2...4, spans: spans))

    let carved = try #require(library.episode(episode.id)?.clips)
    #expect(carved.count == 2)
    #expect(abs(carved[0].durationSeconds - 2) < 0.1)
    #expect(abs(carved[1].durationSeconds - 1) < 0.1)
    #expect(!FileManager.default.fileExists(atPath: episode.folder.appending(path: clips[0].name).path))

    let merged = try await library.mergedAudio(episode.id)
    #expect(abs(try await AudioEditing.duration(of: merged) - 3) < 0.2)
  }

  @Test func narrationDraftOpensEditsAndCommitsATake() async throws {
    let draft = NarrationDraft(storage: NarrationStorage(root: root.appending(path: "narrations")))
    let source = try await take(seconds: 2)

    try await draft.open(postUID: "https://me.blog/1.html", audio: source.url)
    #expect(draft.isOpen(for: "https://me.blog/1.html"))
    #expect(draft.segments.count == 1)

    try await draft.appendRecording(try await take(seconds: 1))
    #expect(draft.isDirty)

    let committed = try await draft.commit()
    defer { try? FileManager.default.removeItem(at: committed.url) }

    #expect(abs(try await AudioEditing.duration(of: committed.url) - 3) < 0.2)
    #expect(draft.postUID == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "narrations/https-me-blog-1-html").path))
  }
}
