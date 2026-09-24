import Foundation

nonisolated struct StorageError: LocalizedError, Sendable {
  let message: String
  var errorDescription: String? { message }
}

nonisolated struct SegmentFolder: Sendable {
  static let exportedFilename = "exported.m4a"
  static let segmentExtension = "m4a"

  let url: URL
  let infoFilename: String

  private var infoURL: URL { url.appending(path: infoFilename) }

  var exists: Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  func read() -> SegmentInfo? {
    guard let data = try? Data(contentsOf: infoURL),
          var info = try? JSONDecoder().decode(SegmentInfo.self, from: data),
          !info.clips.isEmpty else {
      return nil
    }

    info = hydrated(info)
    return info
  }

  func write(_ info: SegmentInfo) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(info).write(to: infoURL, options: .atomic)
  }

  func requireInfo() throws -> SegmentInfo {
    guard exists else {
      throw StorageError(message: "That recording is no longer available.")
    }

    guard let info = read() else {
      throw StorageError(message: "That recording could not be read.")
    }

    return info
  }

  func append(_ source: URL, durationSeconds: Double, waveform: [Float]) throws -> SegmentInfo {
    let existing = try requireInfo()
    let name = try place(source)

    do {
      let clip = ClipMeta(name: name, durationSeconds: durationSeconds, sizeBytes: size(of: name), waveform: waveform)
      let info = existing.with(clipMeta: existing.clipMeta + [clip])
      deleteExported()
      try write(info)
      return info
    } catch {
      try? FileManager.default.removeItem(at: url.appending(path: name))
      throw error
    }
  }

  func replaceClips(_ clipMeta: [ClipMeta]) throws -> SegmentInfo {
    let existing = try requireInfo()
    let info = existing.with(clipMeta: clipMeta.map(hydrated))
    deleteExported()
    try write(info)
    pruneOrphans(keeping: info.clips)
    return info
  }

  func place(_ source: URL) throws -> String {
    let name = "segment-\(nextSegmentIndex()).\(Self.segmentExtension)"
    try FileManager.default.moveItem(at: source, to: url.appending(path: name))
    return name
  }

  func deleteExported() {
    try? FileManager.default.removeItem(at: url.appending(path: Self.exportedFilename))
  }

  func size(of clipName: String) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.appending(path: clipName).path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }

  func isComplete(_ info: SegmentInfo) -> Bool {
    info.clipMeta.allSatisfy { $0.durationSeconds > 0 && size(of: $0.name) > 0 }
  }

  private func hydrated(_ info: SegmentInfo) -> SegmentInfo {
    info.with(clipMeta: info.clipMeta.map(hydrated))
  }

  private func hydrated(_ clip: ClipMeta) -> ClipMeta {
    guard clip.sizeBytes <= 0 else { return clip }
    var copy = clip
    copy.sizeBytes = size(of: clip.name)
    return copy
  }

  private func segmentFiles() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    return names.filter { $0.firstMatch(of: SegmentName.pattern) != nil }
  }

  private func nextSegmentIndex() -> Int {
    let highest = segmentFiles()
      .compactMap { name -> Int? in
        guard let match = name.firstMatch(of: SegmentName.pattern) else { return nil }
        return match.output.1.flatMap { Int($0) } ?? 1
      }
      .max() ?? 0

    return highest + 1
  }

  private func pruneOrphans(keeping clips: [String]) {
    let kept = Set(clips)

    for name in segmentFiles() where !kept.contains(name) {
      try? FileManager.default.removeItem(at: url.appending(path: name))
    }
  }
}

private nonisolated enum SegmentName {
  static var pattern: Regex<(Substring, Substring?)> { #/^segment(?:-(\d+))?\./#.ignoresCase() }
}

extension SegmentInfo {
  nonisolated func with(clipMeta: [ClipMeta]) -> SegmentInfo {
    SegmentInfo(
      clipMeta: clipMeta,
      createdAt: createdAt,
      title: title,
      postID: postID,
      postURL: postURL,
      publishedAt: publishedAt
    )
  }
}
