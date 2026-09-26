import Foundation
import Testing
@testable import Wavelength

struct SegmentInfoTests {
  @Test func decodesTheReactNativeEpisodeFormat() throws {
    let json = """
    {
      "clip_meta": [
        {"name": "segment-1.m4a", "duration_seconds": 12.5, "size_bytes": 2048, "waveform": [0.1, 0.9]},
        {"name": "segment-2.m4a", "duration_seconds": 7.5, "size_bytes": 1024, "waveform": [0.4]}
      ],
      "clips": ["segment-1.m4a", "segment-2.m4a"],
      "created_at": "2026-09-01T10:00:00.000Z",
      "duration_seconds": 20,
      "title": "Morning Show",
      "waveform": [],
      "post_id": "123",
      "post_url": "https://me.micro.blog/2026/09/01/morning.html"
    }
    """
    let info = try JSONDecoder().decode(SegmentInfo.self, from: Data(json.utf8))

    #expect(info.clips == ["segment-1.m4a", "segment-2.m4a"])
    #expect(info.durationSeconds == 20)
    #expect(info.title == "Morning Show")
    #expect(info.postID == "123")
    #expect(info.waveform.count == Waveform.sampleCount)
  }

  @Test func migratesEpisodesWithoutClipMeta() throws {
    let json = #"{"clips": ["a.m4a", "b.m4a"], "created_at": "x", "duration_seconds": 10, "waveform": [0.5]}"#
    let info = try JSONDecoder().decode(SegmentInfo.self, from: Data(json.utf8))

    #expect(info.clipMeta.map(\.durationSeconds) == [5, 5])
    #expect(info.clipMeta[0].waveform == [0.5])
    #expect(info.clipMeta[1].waveform.isEmpty)
  }

  @Test func encodesSnakeCaseKeysAndOmitsEmptyLinks() throws {
    let info = SegmentInfo(clipMeta: [ClipMeta(name: "segment-1.m4a", durationSeconds: 3)], createdAt: "now", title: "T", postID: " ")
    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(info)) as? [String: Any])

    #expect(object["clip_meta"] != nil)
    #expect(object["created_at"] as? String == "now")
    #expect(object["duration_seconds"] as? Double == 3)
    #expect(object["post_id"] == nil)
  }
}

struct SegmentCarvingTests {
  private let spans = [
    SegmentCarving.Span(name: "a", start: 0, duration: 4),
    SegmentCarving.Span(name: "b", start: 4, duration: 6),
  ]

  @Test func deletingInsideOneSegmentKeepsBothSides() {
    let plan = SegmentCarving.plan(.delete, range: 1...2, spans: spans)

    #expect(plan == ["a": [0..<1, 2..<4]])
  }

  @Test func deletingAcrossSegmentsTrimsEachSide() {
    let plan = SegmentCarving.plan(.delete, range: 3...5, spans: spans)

    #expect(plan == ["a": [0..<3], "b": [1..<6]])
  }

  @Test func deletingAWholeSegmentRemovesIt() {
    let plan = SegmentCarving.plan(.delete, range: 3.99...10, spans: spans)

    #expect(plan == ["b": []])
  }

  @Test func splittingARangeCutsAtBothEdges() {
    let plan = SegmentCarving.plan(.split, range: 1...2, spans: spans)

    #expect(plan == ["a": [0..<1, 1..<2, 2..<4]])
  }

  @Test func splittingAtASegmentEdgeLeavesThatSegmentAlone() {
    let plan = SegmentCarving.plan(.split, range: 4...5, spans: spans)

    #expect(plan == ["b": [0..<1, 1..<6]])
  }

  @Test func tinyRangesChangeNothing() {
    #expect(SegmentCarving.plan(.delete, range: 1...1.01, spans: spans).isEmpty)
  }
}

@MainActor
final class EpisodeStorageTests {
  let root = FileManager.default.temporaryDirectory.appending(path: "wavelength-tests-\(UUID().uuidString)")
  var storage: EpisodeStorage { EpisodeStorage(root: root) }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  private func makeAudio(_ bytes: Int = 64) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "take-\(UUID().uuidString).m4a")
    try Data(repeating: 1, count: bytes).write(to: url)
    return url
  }

  @Test func createsAndListsEpisodes() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [0.5], title: "First")

    #expect(episode.clips.map(\.name) == ["segment-1.m4a"])
    #expect(episode.clips[0].sizeBytes == 64)
    #expect(storage.list().map(\.title) == ["First"])
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "\(episode.id)/episode.json").path))
  }

  @Test func appendsUsingTheNextFreeSegmentName() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [])
    let updated = try storage.append(makeAudio(), to: episode.id, durationSeconds: 2, waveform: [])

    #expect(updated.clips.map(\.name) == ["segment-1.m4a", "segment-2.m4a"])
    #expect(updated.durationSeconds == 6)
  }

  @Test func replacingClipsPrunesOrphanedSegmentFiles() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [])
    let appended = try storage.append(makeAudio(), to: episode.id, durationSeconds: 2, waveform: [])
    let reordered = try storage.replaceClips(of: episode.id, with: [appended.clips[1]])

    #expect(reordered.clips.map(\.name) == ["segment-2.m4a"])
    #expect(!FileManager.default.fileExists(atPath: episode.folder.appending(path: "segment-1.m4a").path))
  }

  @Test func publishingRecordsAndClearsTheLink() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [])
    let published = try storage.markPublished(episode.id, postID: "7", postURL: "https://a/7")

    #expect(published.isPublished)
    #expect(published.info.publishedAt != nil)
    #expect(try !storage.clearPublishLink(episode.id).isPublished)
  }

  @Test func duplicatesCopySegmentsButNotThePostLink() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [], title: "Show")
    _ = try storage.markPublished(episode.id, postID: "1", postURL: "https://a/1")
    let copy = try storage.duplicate(episode.id)

    #expect(copy.title == "Show Copy")
    #expect(!copy.isPublished)
    #expect(copy.id != episode.id)
    #expect(FileManager.default.fileExists(atPath: copy.folder.appending(path: "segment-1.m4a").path))
  }

  @Test func renameRejectsEmptyTitles() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [])

    #expect(throws: StorageError.self) { try storage.rename(episode.id, to: "  ") }
    #expect(try storage.rename(episode.id, to: "New").title == "New")
  }

  @Test func deletesEpisodeFolders() throws {
    let episode = try storage.create(from: makeAudio(), durationSeconds: 4, waveform: [])
    try storage.delete(episode.id)

    #expect(storage.list().isEmpty)
  }

  @Test func narrationDraftIDsAreFilesystemSafe() {
    #expect(NarrationStorage.draftID(for: " https://Me.blog/2026/1.html ") == "https-me-blog-2026-1-html")
  }
}
