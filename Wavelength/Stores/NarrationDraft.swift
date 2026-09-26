import Foundation
import Observation

@Observable
final class NarrationDraft: SegmentEditing {
  private(set) var postUID: String?
  private(set) var info: SegmentInfo?
  private(set) var isLoading = false
  private(set) var isWorking = false
  private(set) var isDirty = false

  @ObservationIgnored private let storage: NarrationStorage
  @ObservationIgnored private var generation = 0

  init(storage: NarrationStorage = .standard) {
    self.storage = storage
  }

  var segments: [ClipMeta] { info?.clipMeta ?? [] }
  var segmentFolder: URL? { postUID.flatMap { storage.folder(for: $0)?.url } }
  var isLocked: Bool { false }
  var durationSeconds: Double { info?.durationSeconds ?? 0 }
  var waveform: [Float] { info?.waveform ?? [] }
  var totalSizeBytes: Int64 { info?.totalSizeBytes ?? 0 }

  func isOpen(for uid: String) -> Bool {
    postUID == uid && info != nil
  }

  func open(postUID uid: String, audio source: URL) async throws {
    if postUID == uid, info != nil || isLoading {
      return
    }

    discard()
    generation += 1
    let current = generation
    postUID = uid
    isLoading = true
    defer {
      if current == generation {
        isLoading = false
      }
    }

    var downloaded: URL?

    do {
      let local: URL

      if source.isFileURL {
        local = source
      } else {
        let (temporary, _) = try await HTTP.session.download(from: source)
        let destination = AppDirectories.scratchFile("narration-source")
        try FileManager.default.moveItem(at: temporary, to: destination)
        downloaded = destination
        local = destination
      }

      let processed = try await AudioEditing.normalize(local)

      if let downloaded {
        try? FileManager.default.removeItem(at: downloaded)
      }

      guard current == generation else {
        try? FileManager.default.removeItem(at: processed.url)
        return
      }

      do {
        info = try storage.create(for: uid, from: processed.url, durationSeconds: processed.durationSeconds, waveform: processed.waveform)
      } catch {
        try? FileManager.default.removeItem(at: processed.url)
        throw error
      }

      isDirty = false
    } catch {
      if let downloaded {
        try? FileManager.default.removeItem(at: downloaded)
      }

      if current == generation {
        discard()
      }

      throw error
    }
  }

  func appendRecording(_ take: RecordedTake) async throws {
    let folder = try requireFolder()
    info = try folder.append(take.url, durationSeconds: take.durationSeconds, waveform: take.waveform)
    isDirty = true
  }

  func importAudio(from url: URL) async throws {
    let folder = try requireFolder()
    isWorking = true
    defer { isWorking = false }

    let processed = try await Library.normalizeImport(url)

    do {
      info = try folder.append(processed.url, durationSeconds: processed.durationSeconds, waveform: processed.waveform)
      isDirty = true
    } catch {
      try? FileManager.default.removeItem(at: processed.url)
      throw error
    }
  }

  func reorder(_ clips: [ClipMeta]) async throws {
    guard clips.map(\.name) != segments.map(\.name) else { return }
    try replace(clips)
  }

  func deleteSegment(_ clip: ClipMeta) async throws {
    try replace(segments.filter { $0.name != clip.name })
  }

  func split(_ clip: ClipMeta, at seconds: Double) async throws {
    let folder = try requireFolder()
    isWorking = true
    defer { isWorking = false }

    let (first, second) = try await AudioEditing.split(folder.url.appending(path: clip.name), at: seconds, waveform: clip.waveform)
    let firstName = try folder.place(first.url)
    let secondName = try folder.place(second.url)
    let replacement = [
      ClipMeta(name: firstName, durationSeconds: first.durationSeconds, waveform: first.waveform),
      ClipMeta(name: secondName, durationSeconds: second.durationSeconds, waveform: second.waveform),
    ]
    try replace(segments.flatMap { $0.name == clip.name ? replacement : [$0] })
  }

  func commit() async throws -> RecordedTake {
    let folder = try requireFolder()

    guard let info, !info.clips.isEmpty else {
      throw StorageError(message: "This narration has no audio to save.")
    }

    if Formatting.isOverUploadLimit(info.totalSizeBytes) {
      throw APIError(message: Formatting.uploadLimitMessage(info.totalSizeBytes, noun: "narration"))
    }

    isWorking = true
    defer { isWorking = false }

    let take = AppDirectories.scratchFile("narration-take")
    try await AudioEditing.merge(info.clips.map { folder.url.appending(path: $0) }, to: take)
    let result = RecordedTake(url: take, durationSeconds: info.durationSeconds, waveform: info.waveform)
    discard()
    return result
  }

  func discard() {
    generation += 1

    if let postUID {
      storage.delete(for: postUID)
    }

    postUID = nil
    info = nil
    isDirty = false
    isLoading = false
  }

  func carve(keeping plan: [String: [Range<Double>]]) async throws {
    guard !plan.isEmpty else { return }

    let folder = try requireFolder()
    let draftUID = postUID
    isWorking = true
    defer { isWorking = false }

    let original = segments.map(\.name)
    let carved = try await folder.carve(segments, keeping: plan)
    let added = carved.map(\.name).filter { !original.contains($0) }

    guard postUID == draftUID, segments.map(\.name) == original else {
      folder.discard(added)
      throw StorageError(message: "The segments changed while they were being edited.")
    }

    do {
      try replace(carved, in: folder)
    } catch {
      folder.discard(added)
      throw error
    }
  }

  private func replace(_ clips: [ClipMeta], in folder: SegmentFolder? = nil) throws {
    guard !clips.isEmpty else {
      throw StorageError(message: "Narration needs at least one segment.")
    }

    info = try (folder ?? requireFolder()).replaceClips(clips)
    isDirty = true
  }

  private func requireFolder() throws -> SegmentFolder {
    guard let postUID, let folder = storage.folder(for: postUID), folder.exists else {
      throw StorageError(message: "That narration is no longer available.")
    }

    return folder
  }
}
