import Foundation

nonisolated enum NarrateHTML {
  struct Palette {
    let background: String
    let ink: String
    let inkSoft: String
    let isDark: Bool

    static let light = Palette(background: "#fffaf0", ink: "#24180d", inkSoft: "#756657", isDark: false)
    static let dark = Palette(background: "#15100b", ink: "#fff7e8", inkSoft: "#d9c0a8", isDark: true)
  }

  static func build(title: String, content: String, palette: Palette, fontSize: Int = 20) -> String {
    let body = PostContent.stripAudioTags(content)
    let safeTitle = escape(title.trimmed)
    let titleHTML = safeTitle.isEmpty ? "" : "<h1>\(safeTitle)</h1>"

    return """
    <!doctype html>
    <html class="\(palette.isDark ? "dark" : "light")">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        html, body {
          margin: 0;
          padding: 0;
          background: \(escape(palette.background));
          color: \(escape(palette.ink));
          font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
          font-size: \(fontSize)px;
          line-height: 1.6;
        }
        body {
          padding: 40px 32px 64px;
        }
        main {
          max-width: 720px;
          margin: 0 auto;
        }
        h1 {
          font-size: 1.6em;
          font-weight: 800;
          line-height: 1.25;
          margin: 0 0 20px;
        }
        .post :first-child {
          margin-top: 0;
        }
        img, video {
          max-width: 100%;
          height: auto;
          border-radius: 8px;
        }
        a {
          color: \(escape(palette.ink));
        }
        blockquote {
          margin-left: 0;
          padding-left: 16px;
          border-left: 3px solid #ff8800;
          color: \(escape(palette.inkSoft));
        }
        figcaption, .post .caption {
          color: \(escape(palette.inkSoft));
        }
      </style>
    </head>
    <body>
      <main>
        \(titleHTML)
        <div class="post">\(body)</div>
      </main>
    </body>
    </html>
    """
  }

  static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
