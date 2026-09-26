import Foundation
import Observation

nonisolated struct RecordedTake: Sendable, Hashable {
  let url: URL
  let durationSeconds: Double
  let waveform: [Float]
}

protocol SegmentEditing: AnyObject {
  var segments: [ClipMeta] { get }
  var segmentFolder: URL? { get }
  var isLocked: Bool { get }
  var isWorking: Bool { get }

  func appendRecording(_ take: RecordedTake) async throws
  func importAudio(from url: URL) async throws
  func reorder(_ clips: [ClipMeta]) async throws
  func deleteSegment(_ clip: ClipMeta) async throws
  func split(_ clip: ClipMeta, at seconds: Double) async throws
  func carve(keeping plan: [String: [Range<Double>]]) async throws
}

@Observable
final class Library {
  private(set) var episodes: [Episode] = []
  private(set) var isLoading = false
  private(set) var didHydrate = false
  private(set) var workingEpisodeIDs: Set<String> = []

  @ObservationIgnored let storage: EpisodeStorage
  @ObservationIgnored private let session: Session
  @ObservationIgnored private let posts: PostsStore
  @ObservationIgnored private var mergedFingerprints: [String: String] = [:]

  init(storage: EpisodeStorage = .standard, session: Session, posts: PostsStore) {
    self.storage = storage
    self.session = session
    self.posts = posts
  }

  var sortedEpisodes: [Episode] {
    episodes.sorted { $0.sortKey > $1.sortKey }
  }

  func episode(_ id: String?) -> Episode? {
    guard let id else { return nil }
    return episodes.first { $0.id == id }
  }

  func episode(forPostUID uid: String?, postURL: String? = nil) -> Episode? {
    if let uid = uid.nonEmpty, let match = episodes.first(where: { $0.postID == uid }) {
      return match
    }

    if let url = postURL.nonEmpty {
      return episodes.first { $0.postURL == url }
    }

    return nil
  }

  func isWorking(_ id: String) -> Bool {
    workingEpisodeIDs.contains(id)
  }

  func refresh() {
    isLoading = true
    episodes = storage.list()
    didHydrate = true
    isLoading = false
  }

  func create(from take: RecordedTake) throws -> Episode {
    let episode = try storage.create(from: take.url, durationSeconds: take.durationSeconds, waveform: take.waveform)
    episodes.append(episode)
    return episode
  }

  func append(_ take: RecordedTake, to id: String) throws {
    apply(try storage.append(take.url, to: id, durationSeconds: take.durationSeconds, waveform: take.waveform))
  }

  func importAudio(from url: URL, into id: String) async throws {
    try await working(id) {
      let processed = try await Self.normalizeImport(url)

      do {
        apply(try storage.append(processed.url, to: id, durationSeconds: processed.durationSeconds, waveform: processed.waveform))
      } catch {
        try? FileManager.default.removeItem(at: processed.url)
        throw error
      }
    }
  }

  func reorder(_ id: String, clips: [ClipMeta]) throws {
    guard let episode = episode(id), !episode.isPublished else { return }
    guard clips.map(\.name) != episode.clips.map(\.name) else { return }
    apply(try storage.replaceClips(of: id, with: clips))
  }

  func deleteSegment(_ id: String, clip: ClipMeta) throws {
    guard let episode = episode(id), !episode.isPublished else { return }
    apply(try storage.replaceClips(of: id, with: episode.clips.filter { $0.name != clip.name }))
  }

  func split(_ id: String, clip: ClipMeta, at seconds: Double) async throws {
    guard let episode = episode(id), !episode.isPublished else { return }

    try await working(id) {
      let (first, second) = try await AudioEditing.split(episode.url(for: clip), at: seconds, waveform: clip.waveform)
      let folder = storage.folder(id)
      let firstName = try folder.place(first.url)
      let secondName = try folder.place(second.url)
      let replacement = [
        ClipMeta(name: firstName, durationSeconds: first.durationSeconds, waveform: first.waveform),
        ClipMeta(name: secondName, durationSeconds: second.durationSeconds, waveform: second.waveform),
      ]
      guard let current = self.episode(id)?.clips, current.contains(where: { $0.name == clip.name }) else {
        try? FileManager.default.removeItem(at: folder.url.appending(path: firstName))
        try? FileManager.default.removeItem(at: folder.url.appending(path: secondName))
        throw StorageError(message: "That segment changed while it was being split.")
      }

      apply(try storage.replaceClips(of: id, with: current.flatMap { $0.name == clip.name ? replacement : [$0] }))
    }
  }

  func carve(_ id: String, keeping plan: [String: [Range<Double>]]) async throws {
    guard let episode = episode(id), !episode.isPublished, !plan.isEmpty else { return }

    try await working(id) {
      let folder = storage.folder(id)
      let original = episode.clips.map(\.name)
      let carved = try await folder.carve(episode.clips, keeping: plan)
      let added = carved.map(\.name).filter { !original.contains($0) }

      guard self.episode(id)?.clips.map(\.name) == original else {
        folder.discard(added)
        throw StorageError(message: "The segments changed while they were being edited.")
      }

      guard !carved.isEmpty else {
        folder.discard(added)
        throw StorageError(message: "A recording needs at least one segment.")
      }

      apply(try storage.replaceClips(of: id, with: carved))
    }
  }

  func rename(_ id: String, to title: String) throws {
    guard let episode = episode(id), title.trimmed != episode.title, !title.trimmed.isEmpty else { return }
    apply(try storage.rename(id, to: title))
  }

  func duplicate(_ id: String) throws -> Episode {
    let copy = try storage.duplicate(id)
    episodes.append(copy)
    return copy
  }

  func delete(_ id: String, deletingPost: Bool = false) async throws {
    if deletingPost, let postURL = episode(id)?.postURL {
      try await session.requireMicropub("delete a post").delete(postURL: postURL)
      await posts.refresh()
    }

    try storage.delete(id)
    episodes.removeAll { $0.id == id }
    mergedFingerprints[id] = nil
  }

  func markPublished(_ id: String, postID: String?, postURL: String?) throws {
    apply(try storage.markPublished(id, postID: postID, postURL: postURL))
  }

  func clearPublishLink(_ id: String) throws {
    apply(try storage.clearPublishLink(id))
  }

  func mergedAudio(_ id: String) async throws -> URL {
    guard let episode = episode(id), !episode.clips.isEmpty else {
      throw AudioError(message: "This episode has no audio to export.")
    }

    let fingerprint = episode.clips.map(\.name).joined(separator: "|")

    if mergedFingerprints[id] == fingerprint, FileManager.default.fileExists(atPath: episode.exportedURL.path) {
      return episode.exportedURL
    }

    try await AudioEditing.merge(episode.clips.map(episode.url(for:)), to: episode.exportedURL)
    mergedFingerprints[id] = fingerprint
    return episode.exportedURL
  }

  func publishableAudio(_ id: String) async throws -> URL {
    let merged = try await mergedAudio(id)
    let mp3 = merged.deletingPathExtension().appendingPathExtension("mp3")
    try await MP3Encoder.encode(merged, to: mp3)
    return mp3
  }

  static func normalizeImport(_ url: URL) async throws -> ProcessedAudio {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try await AudioEditing.normalize(url)
  }

  private func apply(_ episode: Episode) {
    if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
      episodes[index] = episode
    } else {
      episodes.append(episode)
    }

    if mergedFingerprints[episode.id] != episode.clips.map(\.name).joined(separator: "|") {
      mergedFingerprints[episode.id] = nil
    }
  }

  private func working(_ id: String, _ operation: () async throws -> Void) async throws {
    workingEpisodeIDs.insert(id)
    defer { workingEpisodeIDs.remove(id) }
    try await operation()
  }
}

@Observable
final class EpisodeDocument: SegmentEditing {
  let id: String
  @ObservationIgnored private let library: Library

  init(id: String, library: Library) {
    self.id = id
    self.library = library
  }

  var episode: Episode? { library.episode(id) }
  var segments: [ClipMeta] { episode?.clips ?? [] }
  var segmentFolder: URL? { episode?.folder }
  var isLocked: Bool { episode?.isPublished ?? true }
  var isWorking: Bool { library.isWorking(id) }

  func appendRecording(_ take: RecordedTake) async throws {
    try library.append(take, to: id)
  }

  func importAudio(from url: URL) async throws {
    try await library.importAudio(from: url, into: id)
  }

  func reorder(_ clips: [ClipMeta]) async throws {
    try library.reorder(id, clips: clips)
  }

  func deleteSegment(_ clip: ClipMeta) async throws {
    try library.deleteSegment(id, clip: clip)
  }

  func split(_ clip: ClipMeta, at seconds: Double) async throws {
    try await library.split(id, clip: clip, at: seconds)
  }

  func carve(keeping plan: [String: [Range<Double>]]) async throws {
    try await library.carve(id, keeping: plan)
  }
}
