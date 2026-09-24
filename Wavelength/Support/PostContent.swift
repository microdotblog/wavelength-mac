import Foundation

nonisolated enum PostKind: String, CaseIterable, Identifiable, Sendable {
  case post
  case podcast
  case narrated

  var id: String { rawValue }

  var label: String {
    switch self {
    case .post: "Post"
    case .podcast: "Podcast"
    case .narrated: "Narrated"
    }
  }

  var symbol: String {
    switch self {
    case .post: "text.alignleft"
    case .podcast: "waveform"
    case .narrated: "mic"
    }
  }
}

nonisolated enum PostContent {
  private static var audioOpenTag: Regex<Substring> { #/<audio\b[^>]*>/#.ignoresCase() }
  private static var audioElement: Regex<Substring> { #/<audio\b[^>]*\/?>(?:\s*<\/audio>)?/#.ignoresCase() }
  private static var hiddenStyle: Regex<Substring> { #/style\s*=\s*["'][^"']*display\s*:\s*none/#.ignoresCase() }
  private static var audioSource: Regex<(Substring, Substring)> { #/\bsrc\s*=\s*["']([^"']+)["']/#.ignoresCase() }

  static func kind(of content: String) -> PostKind {
    let tags = content.matches(of: audioOpenTag).map { String($0.output) }

    if tags.contains(where: { !isHidden($0) }) {
      return .podcast
    }

    if tags.contains(where: isHidden) {
      return .narrated
    }

    return .post
  }

  static func narrationAudioTag(for url: String) -> String {
    "<audio src=\"\(url.trimmingCharacters(in: .whitespaces))\" preload=\"metadata\" style=\"display: none\"></audio>"
  }

  static func stripAudioTags(_ content: String) -> String {
    content.replacing(audioElement, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func stripHiddenAudioTags(_ content: String) -> String {
    content
      .replacing(audioElement) { match in
        isHidden(String(match.output)) ? "" : String(match.output)
      }
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func narrationAudioURL(in content: String) -> String {
    let hiddenTag = content.matches(of: audioElement)
      .map { String($0.output) }
      .first(where: isHidden)

    guard let hiddenTag, let source = hiddenTag.firstMatch(of: audioSource) else {
      return ""
    }

    return String(source.output.1).trimmingCharacters(in: .whitespaces)
  }

  static func applyNarration(to content: String, audioURL: String) -> String {
    let url = audioURL.trimmingCharacters(in: .whitespaces)
    let body = stripHiddenAudioTags(content)

    if url.isEmpty {
      return body
    }

    if body.isEmpty {
      return narrationAudioTag(for: url)
    }

    return "\(narrationAudioTag(for: url))\n\(body)"
  }

  static func plainText(_ html: String) -> String {
    decodeEntities(
      html
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    )
    .trimmingCharacters(in: .whitespaces)
  }

  static func firstPlainLine(_ html: String) -> String {
    let firstBlock = html
      .components(separatedBy: #/<\/p>|<br\s*\/?>|\n/#.ignoresCase())
      .first ?? html
    return plainText(firstBlock)
  }

  static func decodeEntities(_ value: String) -> String {
    value.replacing(#/&(#x[0-9a-fA-F]+|#\d+|amp|apos|gt|lt|nbsp|quot);/#.ignoresCase()) { match in
      let entity = String(match.output.1).lowercased()

      switch entity {
      case "amp": return "&"
      case "apos": return "'"
      case "gt": return ">"
      case "lt": return "<"
      case "nbsp": return " "
      case "quot": return "\""
      default:
        let scalar: UInt32? = entity.hasPrefix("#x")
          ? UInt32(entity.dropFirst(2), radix: 16)
          : UInt32(entity.dropFirst())
        return scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.output.0)
      }
    }
  }

  private static func isHidden(_ tag: String) -> Bool {
    tag.contains(hiddenStyle)
  }
}

private extension String {
  nonisolated func components(separatedBy regex: Regex<Substring>) -> [String] {
    split(separator: regex, omittingEmptySubsequences: false).map(String.init)
  }
}
