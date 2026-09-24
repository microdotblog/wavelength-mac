import Foundation

nonisolated struct EpisodeStorage: Sendable {
  static let infoFilename = "episode.json"

  let root: URL

  static var standard: EpisodeStorage {
    EpisodeStorage(root: AppDirectories.support.appending(path: "episodes"))
  }

  func folder(_ id: String) -> SegmentFolder {
    SegmentFolder(url: root.appending(path: id), infoFilename: Self.infoFilename)
  }

  func episode(_ id: String) -> Episode? {
    let folder = folder(id)

    guard let info = folder.read() else { return nil }

    return Episode(id: id, folder: folder.url, info: info)
  }

  func list() -> [Episode] {
    ensureRoot()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.compactMap(episode)
  }

  func create(from recording: URL, durationSeconds: Double, waveform: [Float], title: String? = nil) throws -> Episode {
    let now = Date()
    let (id, folder) = try makeFolder(for: now)

    do {
      let name = try folder.place(recording)
      let clip = ClipMeta(name: name, durationSeconds: durationSeconds, sizeBytes: folder.size(of: name), waveform: waveform)
      let info = SegmentInfo(
        clipMeta: [clip],
        createdAt: Formatting.isoString(now),
        title: title.nonEmpty ?? Formatting.episodeTitle(for: now)
      )
      try folder.write(info)
      return Episode(id: id, folder: folder.url, info: info)
    } catch {
      try? FileManager.default.removeItem(at: folder.url)
      throw error
    }
  }

  func append(_ source: URL, to id: String, durationSeconds: Double, waveform: [Float]) throws -> Episode {
    let folder = folder(id)
    let info = try folder.append(source, durationSeconds: durationSeconds, waveform: waveform)
    return Episode(id: id, folder: folder.url, info: info)
  }

  func replaceClips(of id: String, with clipMeta: [ClipMeta]) throws -> Episode {
    let folder = folder(id)
    let info = try folder.replaceClips(clipMeta)
    return Episode(id: id, folder: folder.url, info: info)
  }

  func rename(_ id: String, to title: String) throws -> Episode {
    guard let title = title.nonEmptyValue else {
      throw StorageError(message: "Episode title cannot be empty.")
    }

    return try update(id) { $0.title = title }
  }

  func markPublished(_ id: String, postID: String?, postURL: String?) throws -> Episode {
    guard postID.nonEmpty != nil || postURL.nonEmpty != nil else {
      throw StorageError(message: "A published post id or URL is required.")
    }

    return try update(id) { info in
      info.postID = postID.nonEmpty ?? info.postID
      info.postURL = postURL.nonEmpty ?? info.postURL
      info.publishedAt = Formatting.isoString(Date())
    }
  }

  func clearPublishLink(_ id: String) throws -> Episode {
    try update(id) { info in
      info.postID = nil
      info.postURL = nil
      info.publishedAt = nil
    }
  }

  func duplicate(_ id: String) throws -> Episode {
    let source = folder(id)
    let existing = try source.requireInfo()
    let now = Date()
    let (newID, folder) = try makeFolder(for: now)

    do {
      for clip in existing.clipMeta {
        try FileManager.default.copyItem(at: source.url.appending(path: clip.name), to: folder.url.appending(path: clip.name))
      }

      let info = SegmentInfo(
        clipMeta: existing.clipMeta,
        createdAt: Formatting.isoString(now),
        title: "\(existing.title ?? id) Copy"
      )
      try folder.write(info)
      return Episode(id: newID, folder: folder.url, info: info)
    } catch {
      try? FileManager.default.removeItem(at: folder.url)
      throw StorageError(message: "This episode is missing one of its segments.")
    }
  }

  func delete(_ id: String) throws {
    let folder = folder(id)

    if folder.exists {
      try FileManager.default.removeItem(at: folder.url)
    }
  }

  private func update(_ id: String, _ change: (inout SegmentInfo) -> Void) throws -> Episode {
    let folder = folder(id)
    var info = try folder.requireInfo()
    change(&info)
    try folder.write(info)
    return Episode(id: id, folder: folder.url, info: info)
  }

  private func makeFolder(for date: Date) throws -> (String, SegmentFolder) {
    ensureRoot()
    let base = Formatting.isoString(date).replacingOccurrences(of: "[:.]", with: "-", options: .regularExpression)
    var candidate = base
    var attempt = 1

    while folder(candidate).exists {
      attempt += 1
      candidate = "\(base)-\(attempt)"
    }

    let folder = folder(candidate)
    try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
    return (candidate, folder)
  }

  private func ensureRoot() {
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
}

nonisolated enum AppDirectories {
  static var support: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "Wavelength")
  }

  static var scratch: URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "Wavelength")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static func scratchFile(_ prefix: String, extension ext: String = "m4a") -> URL {
    scratch.appending(path: "\(prefix)-\(UUID().uuidString).\(ext)")
  }
}
