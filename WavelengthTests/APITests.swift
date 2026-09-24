import AppKit
import Foundation
import MediaPlayer
import Testing
@testable import Wavelength

struct MicropubTests {
  @Test func newPostFormMatchesTheMicropubContract() {
    let form = Micropub.newPostForm(
      Micropub.NewPost(
        title: "Ep 1",
        content: "Notes",
        audioURL: " https://cdn/a.mp3 ",
        status: "draft",
        summary: " ",
        categories: ["podcast", " "],
        syndicates: ["https://bsky"]
      ),
      destination: "https://me.micro.blog/"
    )

    #expect(form.map(\.0) == ["audio", "content", "h", "name", "mp-destination", "post-status", "category[]", "mp-syndicate-to[]"])
    #expect(form.first { $0.0 == "audio" }?.1 == "https://cdn/a.mp3")
    #expect(form.first { $0.0 == "h" }?.1 == "entry")
  }

  @Test func formEncodingUsesPlusForSpaces() {
    let body = String(decoding: HTTP.formEncode([("name", "Hello world & more"), ("category[]", "a")]), as: UTF8.self)
    #expect(body == "name=Hello+world+%26+more&category%5B%5D=a")
  }

  @Test func postsSkipDraftsAndSortNewestFirst() {
    let payload: JSONObject = ["items": [
      ["properties": ["uid": ["1"], "url": ["https://a/1"], "published": ["2026-01-01T00:00:00Z"], "content": ["old"]]],
      ["properties": ["uid": ["2"], "url": ["https://a/2"], "published": ["2026-03-01T00:00:00Z"], "content": ["new"]]],
      ["properties": ["uid": ["3"], "url": ["https://a/3"], "post-status": ["draft"]]],
      ["properties": ["url": ["https://a/4"]]],
    ]]

    #expect(Micropub.posts(from: payload).map(\.uid) == ["2", "1"])
  }

  @Test func destinationsFallBackToHostnames() {
    let payload: JSONObject = ["destination": [
      ["uid": "https://one.blog/", "name": "One", "microblog-default": true],
      ["uid": "https://two.blog/"],
      ["name": "missing uid"],
    ]]
    let destinations = Micropub.destinations(from: payload)

    #expect(destinations.map(\.name) == ["One", "two.blog"])
    #expect(destinations.map(\.isDefault) == [true, false])
  }

  @Test func sourceReadsPropertyArrays() {
    let source = Micropub.source(from: ["properties": [
      "uid": ["42"],
      "name": ["Title"],
      "content": ["Body"],
      "category": ["a", "b"],
    ]])

    #expect(source.uid == "42")
    #expect(source.status == "published")
    #expect(source.categories == ["a", "b"])
  }

  @Test func updateBodyReplacesPropertiesAsArrays() throws {
    let body = Micropub.updateBody(
      Micropub.PostUpdate(url: " https://a/1 ", title: "T", content: "C", status: " ", summary: " S ", categories: ["x", ""], audioURL: "https://a/n.m4a"),
      destination: "https://me.blog/"
    )
    let replace = try #require(body["replace"] as? JSONObject)

    #expect(body["action"] as? String == "update")
    #expect(body["url"] as? String == "https://a/1")
    #expect(body["mp-destination"] as? String == "https://me.blog/")
    #expect(replace["post-status"] as? [String] == ["published"])
    #expect(replace["summary"] as? [String] == ["S"])
    #expect(replace["category"] as? [String] == ["x"])
    #expect(replace["audio"] as? [String] == ["https://a/n.m4a"])
  }

  @Test func updateBodyOmitsAudioWhenRemovingNarration() {
    let body = Micropub.updateBody(
      Micropub.PostUpdate(url: "u", title: "", content: "", status: "published", summary: "", categories: []),
      destination: nil
    )

    #expect((body["replace"] as? JSONObject)?["audio"] == nil)
    #expect(body["mp-destination"] == nil)
  }

  @Test func multipartBodyCarriesDestinationAndFile() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "audio-\(UUID().uuidString).mp3")
    let body = FileManager.default.temporaryDirectory.appending(path: "body-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: body)
    }
    try Data("MP3DATA".utf8).write(to: source)

    try Micropub.writeMultipartBody(to: body, boundary: "B", destination: "https://me.blog/", fileURL: source, filename: "ep\"1.mp3")
    let text = try String(contentsOf: body, encoding: .utf8)

    #expect(text == "--B\r\nContent-Disposition: form-data; name=\"mp-destination\"\r\n\r\nhttps://me.blog/\r\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ep1.mp3\"\r\nContent-Type: audio/mpeg\r\n\r\nMP3DATA\r\n--B--\r\n")
  }

  @Test func nullErrorsAreNotFailures() {
    let ok = HTTPURLResponse(url: URL(string: "https://a")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    #expect(!HTTP.isFailure(["error": NSNull()], ok))
    #expect(HTTP.isFailure(["error": "invalid_token"], ok))
  }

  @Test func audioMimeTypes() {
    #expect(Micropub.audioMimeType(for: URL(filePath: "/x/episode.mp3")) == "audio/mpeg")
    #expect(Micropub.audioMimeType(for: URL(filePath: "/x/narration.m4a")) == "audio/mp4")
  }
}

struct AuthTests {
  @Test func authorizationURLCarriesWavelengthParameters() throws {
    let url = MicroBlogAuth.authorizationURL(state: "abc")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

    #expect(values["client_id"] == "https://micro.blog/wavelength/")
    #expect(values["redirect_uri"] == "wavelength://auth/callback")
    #expect(values["scope"] == "read write")
    #expect(values["state"] == "abc")
    #expect(values["app"] == "1")
  }

  @Test func readsCallbackParameters() {
    let parameters = MicroBlogAuth.callbackParameters(URL(string: "wavelength://auth/callback?code=xyz&state=abc")!)
    #expect(parameters.code == "xyz")
    #expect(parameters.state == "abc")
  }

  @Test func readsLegacyTokenLinks() {
    #expect(MicroBlogAuth.legacyToken(from: URL(string: "wavelength://signin/TOKEN123")!) == "TOKEN123")
    #expect(MicroBlogAuth.legacyToken(from: URL(string: "wavelength://auth/callback?code=1")!) == nil)
  }

  @Test func statesAreRandomHex() {
    let state = MicroBlogAuth.makeState()
    #expect(state.count == 32)
    #expect(state != MicroBlogAuth.makeState())
  }
}

struct DiscoverParsingTests {
  @Test func normalizesJSONFeedItems() throws {
    let payload: JSONObject = ["items": [[
      "id": "99",
      "url": "https://a/99",
      "content_html": "<p>My Show: example.com</p><img src=\"https://img/cover.jpg\">",
      "date_published": "2026-09-01T10:00:00Z",
      "author": [
        "name": "Vincent",
        "avatar": "https://cdn.micro.blog/photos/96/https%3A%2F%2Favatars%2Fv.jpg",
        "_microblog": ["username": "vincent"],
      ],
      "_microblog": [
        "audio": ["url": "https://a/99.mp3", "duration_seconds": "125", "duration_display": "2:05"],
        "is_bookmark": true,
        "date_relative": "2 hours ago",
      ],
    ]]]

    let post = try #require(DiscoverAPI.posts(from: payload).first)

    #expect(post.title == "My Show")
    #expect(post.imageURL?.absoluteString == "https://img/cover.jpg")
    #expect(post.authorAvatar?.absoluteString == "https://avatars/v.jpg")
    #expect(post.durationSeconds == 125)
    #expect(post.isSaved)
    #expect(post.isPlayable)
    #expect(post.timestamp == "2 hours ago")
  }

  @Test func dropsItemsWithoutIDs() {
    #expect(DiscoverAPI.posts(from: ["items": [["url": "https://a"]]]).isEmpty)
  }
}

struct NowPlayingTests {
  @Test func artworkCanBeRenderedOffTheMainThread() async throws {
    let image = NSImage(size: CGSize(width: 8, height: 8))
    image.lockFocus()
    NSColor.orange.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    image.unlockFocus()
    let data = try #require(image.tiffRepresentation)
    nonisolated(unsafe) let artwork = NowPlaying.artwork(from: data, size: image.size)

    let rendered = await Task.detached {
      artwork.image(at: CGSize(width: 4, height: 4))?.size
    }.value

    #expect(rendered != nil)
  }
}
