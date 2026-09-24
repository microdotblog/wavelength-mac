import Foundation

nonisolated struct BlogDestination: Identifiable, Hashable, Codable, Sendable {
  let uid: String
  let name: String
  var isDefault: Bool = false

  var id: String { uid }
}

nonisolated struct UserProfile: Hashable, Sendable {
  var username: String?
  var name: String?
  var photo: URL?
  var url: URL?
  var defaultSite: String?
  var hasSite: Bool?
}

nonisolated struct Post: Identifiable, Hashable, Sendable {
  let uid: String
  let url: String
  var title: String
  var content: String
  var summary: String
  var status: String
  var publishedAt: String
  var categories: [String] = []

  var id: String { uid }
  var kind: PostKind { PostContent.kind(of: content) }
  var narrationAudioURL: String { PostContent.narrationAudioURL(in: content) }
  var publishedDate: Date? { Formatting.parseDate(publishedAt) }

  var displayTitle: String {
    if !title.trimmed.isEmpty {
      return title.trimmed
    }

    let firstLine = PostContent.firstPlainLine(content)
    return firstLine.isEmpty ? "Untitled" : firstLine
  }

  var displaySummary: String {
    let heading = displayTitle
    let fromSummary = summary.trimmed
    let fromContent = PostContent.plainText(content)

    if !fromSummary.isEmpty, fromSummary != heading {
      return fromSummary
    }

    if !fromContent.isEmpty, fromContent != heading {
      return fromContent
    }

    return ""
  }
}

nonisolated struct PostSource: Hashable, Sendable {
  var uid: String
  var url: String
  var title: String
  var content: String
  var summary: String
  var status: String
  var categories: [String]
}

nonisolated struct SyndicationTarget: Identifiable, Hashable, Sendable {
  let uid: String
  let name: String

  var id: String { uid }
}

nonisolated struct DiscoverPost: Identifiable, Hashable, Sendable {
  let id: String
  let url: String
  var title: String
  var summary: String
  var authorName: String
  var authorUsername: String
  var authorAvatar: URL?
  var authorURL: URL?
  var audioURL: URL?
  var imageURL: URL?
  var durationSeconds: Int
  var durationDisplay: String
  var dateRelative: String
  var publishedAt: String
  var isPodcast: Bool
  var isSaved: Bool

  var isPlayable: Bool { audioURL != nil }
  var sourceLabel: String { authorName.trimmed.isEmpty ? "Micro.blog" : authorName.trimmed }
  var displayTitle: String { title.trimmed.isEmpty ? sourceLabel : title.trimmed }
  var artworkURL: URL? { imageURL ?? authorAvatar }

  var timestamp: String {
    if !dateRelative.trimmed.isEmpty {
      return dateRelative.trimmed
    }

    return Formatting.parseDate(publishedAt)?.formatted(.dateTime.day().month(.abbreviated).hour().minute()) ?? ""
  }

  var durationLabel: String {
    durationSeconds > 0 ? Formatting.duration(Double(durationSeconds)) : durationDisplay
  }

  var displaySummary: String {
    let text = Formatting.collapseWhitespace(summary)
    return text == title.trimmed ? "" : text
  }
}
