import Foundation
import Testing
@testable import Wavelength

struct PostContentTests {
  @Test func classifiesVisibleAudioAsPodcast() {
    #expect(PostContent.kind(of: "<p>Hi</p><audio src=\"a.mp3\" controls></audio>") == .podcast)
  }

  @Test func classifiesHiddenAudioAsNarrated() {
    let content = PostContent.applyNarration(to: "<p>Hello</p>", audioURL: "https://cdn/n.m4a")
    #expect(PostContent.kind(of: content) == .narrated)
    #expect(PostContent.narrationAudioURL(in: content) == "https://cdn/n.m4a")
  }

  @Test func classifiesPlainTextAsPost() {
    #expect(PostContent.kind(of: "Just words") == .post)
  }

  @Test func applyingNarrationReplacesAnExistingHiddenTag() {
    let first = PostContent.applyNarration(to: "Body", audioURL: "https://a/1.m4a")
    let second = PostContent.applyNarration(to: first, audioURL: "https://a/2.m4a")

    #expect(second == "<audio src=\"https://a/2.m4a\" preload=\"metadata\" style=\"display: none\"></audio>\nBody")
  }

  @Test func removingNarrationKeepsVisibleAudio() {
    let content = "<audio src=\"ep.mp3\" controls></audio>\n" + PostContent.narrationAudioTag(for: "https://a/n.m4a")
    let stripped = PostContent.applyNarration(to: content, audioURL: "")

    #expect(stripped == "<audio src=\"ep.mp3\" controls></audio>")
    #expect(PostContent.kind(of: stripped) == .podcast)
  }

  @Test func narrationOfAnEmptyPostIsJustTheTag() {
    #expect(PostContent.applyNarration(to: "", audioURL: "u") == PostContent.narrationAudioTag(for: "u"))
  }

  @Test func teleprompterStripsAudioAndEscapesTitle() {
    let html = NarrateHTML.build(
      title: "Tom & <Jerry>",
      content: "<p>Read me</p>" + PostContent.narrationAudioTag(for: "x"),
      palette: .light
    )

    #expect(html.contains("<h1>Tom &amp; &lt;Jerry&gt;</h1>"))
    #expect(!html.contains("<audio"))
    #expect(html.contains("<p>Read me</p>"))
  }

  @Test func plainTextDropsMarkdownLinkTargets() {
    #expect(PostContent.plainText("I've added the [listen later API](https://a/b) today") == "I've added the listen later API today")
  }

  @Test func postDisplayFallsBackToFirstLine() {
    let post = Post(uid: "1", url: "u", title: "", content: "<p>First line</p><p>Second</p>", summary: "", status: "published", publishedAt: "")

    #expect(post.displayTitle == "First line")
    #expect(post.displaySummary == "First line Second")
  }
}

struct WaveformTests {
  @Test func downsampleKeepsPeaks() {
    let samples: [Float] = [0, 0.9, 0.1, 0.2, 0.5, 0.3]
    #expect(Waveform.downsample(samples, to: 3) == [0.9, 0.2, 0.5])
  }

  @Test func downsampleClampsShortInput() {
    #expect(Waveform.downsample([-1, 2, 0.5], to: 10) == [0, 1, 0.5])
  }

  @Test func mergeWeightsClipsByDuration() {
    let clips = [
      ClipMeta(name: "a", durationSeconds: 3, waveform: [1]),
      ClipMeta(name: "b", durationSeconds: 1, waveform: [0.5]),
    ]

    #expect(Waveform.merge(clips, to: 4) == [1, 1, 1, 0.5])
  }

  @Test func sliceTakesTheRequestedFraction() {
    let waveform: [Float] = [0.1, 0.2, 0.3, 0.4]
    #expect(Waveform.slice(waveform, from: 0, to: 0.5) == [0.1, 0.2])
    #expect(Waveform.slice(waveform, from: 0.5, to: 1) == [0.3, 0.4])
  }

  @Test func decibelsNormalizeToUnitRange() {
    #expect(Waveform.normalize(decibels: -60) == 0)
    #expect(Waveform.normalize(decibels: 0) == 1)
    #expect(Waveform.normalize(decibels: -30) == 0.5)
    #expect(Waveform.normalize(decibels: -.infinity) == 0)
  }
}

struct FormattingTests {
  @Test func formatsDurations() {
    #expect(Formatting.duration(0) == "0:00")
    #expect(Formatting.duration(65.9) == "1:05")
    #expect(Formatting.duration(3_725) == "1:02:05")
  }

  @Test func formatsFileSizesInDecimalMegabytes() {
    #expect(Formatting.fileSize(0) == "0 MB")
    #expect(Formatting.fileSize(48_200) == "48 KB")
    #expect(Formatting.fileSize(1_500_000) == "1.5 MB")
    #expect(Formatting.fileSize(75_000_000) == "75 MB")
  }

  @Test func enforcesTheUploadLimit() {
    #expect(!Formatting.isOverUploadLimit(75_000_000))
    #expect(Formatting.isOverUploadLimit(75_000_001))
  }

  @Test func buildsUploadFilenamesFromTitles() {
    #expect(Formatting.audioUploadFilename(for: "Café’s Big Episode #3!") == "cafes-big-episode-3.mp3")
    #expect(Formatting.audioUploadFilename(for: "   ") == "exported.mp3")
  }

  @Test func sanitizesExportFilenames() {
    #expect(Formatting.exportFilename(for: "a/b: c?") == "ab c.m4a")
    #expect(Formatting.exportFilename(for: "...") == "Episode.m4a")
  }
}
