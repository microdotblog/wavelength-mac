import Foundation

nonisolated struct ClipMeta: Codable, Hashable, Sendable, Identifiable {
  var name: String
  var durationSeconds: Double
  var sizeBytes: Int64
  var waveform: [Float]

  var id: String { name }

  init(name: String, durationSeconds: Double, sizeBytes: Int64 = 0, waveform: [Float] = []) {
    self.name = name
    self.durationSeconds = durationSeconds.isFinite ? max(durationSeconds, 0) : 0
    self.sizeBytes = max(sizeBytes, 0)
    self.waveform = waveform.filter(\.isFinite).map(Waveform.clamp)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      name: (try? container.decode(String.self, forKey: .name)) ?? "",
      durationSeconds: (try? container.decode(Double.self, forKey: .durationSeconds)) ?? 0,
      sizeBytes: (try? container.decode(Int64.self, forKey: .sizeBytes)) ?? 0,
      waveform: (try? container.decode([Float].self, forKey: .waveform)) ?? []
    )
  }

  enum CodingKeys: String, CodingKey {
    case name
    case durationSeconds = "duration_seconds"
    case sizeBytes = "size_bytes"
    case waveform
  }
}

nonisolated struct SegmentInfo: Codable, Hashable, Sendable {
  var clipMeta: [ClipMeta]
  var clips: [String]
  var createdAt: String
  var durationSeconds: Double
  var title: String?
  var waveform: [Float]
  var postID: String?
  var postURL: String?
  var publishedAt: String?

  enum CodingKeys: String, CodingKey {
    case clipMeta = "clip_meta"
    case clips
    case createdAt = "created_at"
    case durationSeconds = "duration_seconds"
    case title
    case waveform
    case postID = "post_id"
    case postURL = "post_url"
    case publishedAt = "published_at"
  }

  init(
    clipMeta: [ClipMeta],
    createdAt: String,
    title: String? = nil,
    postID: String? = nil,
    postURL: String? = nil,
    publishedAt: String? = nil
  ) {
    let safeMeta = clipMeta.filter { !$0.name.isEmpty }
    self.clipMeta = safeMeta
    self.clips = safeMeta.map(\.name)
    self.createdAt = createdAt
    self.durationSeconds = safeMeta.reduce(0) { $0 + $1.durationSeconds }
    self.title = title
    self.waveform = Waveform.merge(safeMeta)
    self.postID = postID.nonEmpty
    self.postURL = postURL.nonEmpty
    self.publishedAt = publishedAt.nonEmpty
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let clips = (try? container.decode([String].self, forKey: .clips)) ?? []
    let storedMeta = (try? container.decode([ClipMeta].self, forKey: .clipMeta)) ?? []
    let meta: [ClipMeta]

    if storedMeta.count == clips.count {
      meta = storedMeta
    } else {
      let total = (try? container.decode(Double.self, forKey: .durationSeconds)) ?? 0
      let perClip = clips.isEmpty ? 0 : total / Double(clips.count)
      let waveform = (try? container.decode([Float].self, forKey: .waveform)) ?? []
      meta = clips.enumerated().map { index, name in
        ClipMeta(name: name, durationSeconds: perClip, waveform: index == 0 ? waveform : [])
      }
    }

    self.init(
      clipMeta: meta,
      createdAt: (try? container.decode(String.self, forKey: .createdAt)) ?? "",
      title: try? container.decode(String.self, forKey: .title),
      postID: try? container.decode(String.self, forKey: .postID),
      postURL: try? container.decode(String.self, forKey: .postURL),
      publishedAt: try? container.decode(String.self, forKey: .publishedAt)
    )
  }

  var totalSizeBytes: Int64 {
    clipMeta.reduce(0) { $0 + $1.sizeBytes }
  }
}

nonisolated struct Episode: Identifiable, Hashable, Sendable {
  let id: String
  let folder: URL
  var info: SegmentInfo

  var title: String { info.title ?? id }
  var clips: [ClipMeta] { info.clipMeta }
  var durationSeconds: Double { info.durationSeconds }
  var waveform: [Float] { info.waveform }
  var postID: String? { info.postID }
  var postURL: String? { info.postURL }
  var isPublished: Bool { info.postID != nil || info.postURL != nil }
  var createdAt: Date? { Formatting.parseDate(info.createdAt) }
  var publishedAt: Date? { info.publishedAt.flatMap(Formatting.parseDate) }
  var totalSizeBytes: Int64 { info.totalSizeBytes }
  var isOverUploadLimit: Bool { Formatting.isOverUploadLimit(totalSizeBytes) }
  var exportedURL: URL { folder.appending(path: SegmentFolder.exportedFilename) }

  func url(for clip: ClipMeta) -> URL {
    folder.appending(path: clip.name)
  }

  var sortKey: String { info.createdAt }
}

extension Optional where Wrapped == String {
  nonisolated var nonEmpty: String? {
    guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}

extension String {
  nonisolated var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
