import AppKit
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

struct MarkdownHighlighterTests {
  private func styles(_ text: String) -> [String: MarkdownHighlighter.Style] {
    let string = text as NSString
    return Dictionary(
      MarkdownHighlighter.spans(in: text).map { (string.substring(with: $0.range), $0.style) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  @Test func highlightsInlineMarkdown() {
    let found = styles("Say **hi** to _you_ and `code` now")

    #expect(found["**hi**"] == .bold)
    #expect(found["_you_"] == .italic)
    #expect(found["`code`"] == .code)
  }

  @Test func splitsLinksIntoTextAndURL() {
    let found = styles("See [the show](https://example.com/a_b_c) today")

    #expect(found["[the show]"] == .linkText)
    #expect(found["(https://example.com/a_b_c)"] == .linkURL)
  }

  @Test func leavesBareURLsAlone() {
    let spans = MarkdownHighlighter.spans(in: "Listen at https://example.com/my_great_show_ now")

    #expect(spans.isEmpty)
  }

  @Test func highlightsLineLevelMarkdown() {
    let found = styles("# Episode 3\n> A quote\n---\nHi @manton")

    #expect(found["# Episode 3"] == .header)
    #expect(found["> A quote"] == .quote)
    #expect(found["---"] == .divider)
    #expect(found["@manton"] == .username)
  }

  @Test func highlightsHTMLTagsAndAttributes() {
    let found = styles(#"<img src="a.jpg" alt="x">"#)

    #expect(found["<img"] == .tag)
    #expect(found["src"] == .attributeName)
    #expect(found[#""a.jpg""#] == .attributeValue)
  }

  @Test func ignoresUnderscoresInsideWords() {
    #expect(styles("snake_case_name").isEmpty)
  }

  @Test func italicisesTextRightAfterATag() {
    #expect(styles("<p>_Episode notes_</p>")["_Episode notes_"] == .italic)
  }

  @Test func highlightsAttributeValuesWithApostrophes() {
    #expect(styles(#"<img alt="Manton's show">"#)[#""Manton's show""#] == .attributeValue)
  }

  @MainActor
  @Test func stacksBoldAndItalic() throws {
    let storage = NSTextStorage(string: "**_Episode 3_**")
    MarkdownStyle.apply(to: storage)

    let font = try #require(storage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
    let traits = font.fontDescriptor.symbolicTraits
    #expect(traits.contains(.bold))
    #expect(traits.contains(.italic))
  }

  @Test func skipsVeryLongText() {
    let text = String(repeating: "**a** ", count: 1_000)

    #expect(MarkdownHighlighter.spans(in: text).isEmpty)
  }
}

struct MarkdownReturnTests {
  @Test func startsANewParagraph() {
    #expect(MarkdownReturn.newline(after: "First paragraph.") == "\n\n")
  }

  @Test func addsASingleLineOnAnEmptyLine() {
    #expect(MarkdownReturn.newline(after: "") == "\n")
    #expect(MarkdownReturn.newline(after: "First paragraph.\n\n") == "\n")
  }

  @Test func keepsCodeBlocksTight() {
    #expect(MarkdownReturn.newline(after: "```\nlet a = 1") == "\n")
    #expect(MarkdownReturn.newline(after: "```\ncode\n```") == "\n\n")
  }
}

struct MarkdownPasteTests {
  @Test func wrapsSelectedTextInALink() {
    #expect(MarkdownPaste.link(wrapping: "the show", in: " https://example.com/ep/3\n") == "[the show](https://example.com/ep/3)")
  }

  @Test func pastesNormallyWithoutAWebURL() {
    #expect(MarkdownPaste.link(wrapping: "the show", in: "just some words") == nil)
    #expect(MarkdownPaste.link(wrapping: "the show", in: "ftp://example.com/file") == nil)
    #expect(MarkdownPaste.link(wrapping: "the show", in: "https://a.com and more") == nil)
  }

  @Test func replacesALinkWithALink() {
    #expect(MarkdownPaste.link(wrapping: "https://old.com", in: "https://new.com") == nil)
  }

  @Test func needsASelection() {
    #expect(MarkdownPaste.link(wrapping: "", in: "https://example.com") == nil)
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
