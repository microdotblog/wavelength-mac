import Foundation

nonisolated struct NarrationStorage: Sendable {
  static let infoFilename = "draft.json"

  let root: URL

  static var standard: NarrationStorage {
    NarrationStorage(root: AppDirectories.support.appending(path: "narrations"))
  }

  static func draftID(for postUID: String) -> String {
    postUID
      .trimmed
      .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      .lowercased()
  }

  func folder(for postUID: String) -> SegmentFolder? {
    let id = Self.draftID(for: postUID)
    guard !id.isEmpty else { return nil }
    return SegmentFolder(url: root.appending(path: id), infoFilename: Self.infoFilename)
  }

  func create(for postUID: String, from source: URL, durationSeconds: Double, waveform: [Float]) throws -> SegmentInfo {
    guard let folder = folder(for: postUID) else {
      throw StorageError(message: "A post is required to edit narration.")
    }

    if folder.exists {
      try FileManager.default.removeItem(at: folder.url)
    }

    try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)

    let name = try folder.place(source)
    let clip = ClipMeta(name: name, durationSeconds: durationSeconds, sizeBytes: folder.size(of: name), waveform: waveform)
    let info = SegmentInfo(clipMeta: [clip], createdAt: Formatting.isoString(Date()))
    try folder.write(info)
    return info
  }

  func delete(for postUID: String) {
    guard let folder = folder(for: postUID), folder.exists else { return }
    try? FileManager.default.removeItem(at: folder.url)
  }
}
