import Foundation

nonisolated enum Formatting {
  static let uploadLimitBytes: Int64 = 75 * 1000 * 1000

  static func duration(_ seconds: Double) -> String {
    let whole = Int(max(seconds.isFinite ? seconds : 0, 0))
    let hours = whole / 3600
    let minutes = (whole % 3600) / 60
    let remainder = whole % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    } else {
      return String(format: "%d:%02d", minutes, remainder)
    }
  }

  static func preciseDuration(_ seconds: Double) -> String {
    let safe = max(seconds.isFinite ? seconds : 0, 0)
    let tenths = Int((safe * 10).rounded(.down)) % 10
    return "\(duration(safe)).\(tenths)"
  }

  static func fileSize(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 MB" }

    let megabytes = Double(bytes) / 1_000_000

    if megabytes < 0.1 {
      return "\(max(1, Int((Double(bytes) / 1_000).rounded()))) KB"
    }

    if megabytes >= 10 {
      return "\(Int(megabytes.rounded())) MB"
    } else {
      return String(format: "%.1f MB", megabytes)
    }
  }

  static func isOverUploadLimit(_ bytes: Int64) -> Bool {
    bytes > uploadLimitBytes
  }

  static func uploadLimitMessage(_ bytes: Int64, noun: String = "episode") -> String {
    "This \(noun) is \(fileSize(bytes)). Micro.blog uploads must be \(fileSize(uploadLimitBytes)) or smaller."
  }

  static func episodeTitle(for date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
  }

  static func postDate(_ isoString: String) -> String {
    guard let date = parseDate(isoString) else { return "" }
    return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
  }

  static func parseDate(_ isoString: String) -> Date? {
    let trimmed = isoString.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else { return nil }

    if let date = try? Date(trimmed, strategy: .iso8601) {
      return date
    }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: trimmed)
  }

  static func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func exportFilename(for title: String, extension ext: String = "m4a") -> String {
    let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
    var stem = collapseWhitespace(String(title.unicodeScalars.filter { !illegal.contains($0) }))
    stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))

    if stem.count > 80 {
      stem = String(stem.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    if stem.isEmpty {
      stem = "Episode"
    }

    return "\(stem).\(ext)"
  }

  static func audioUploadFilename(for title: String) -> String {
    let folded = title
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.diacriticInsensitive], locale: nil)
      .lowercased()
      .replacingOccurrences(of: "['’]", with: "", options: .regularExpression)
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    return folded.isEmpty ? "exported.mp3" : "\(folded).mp3"
  }

  static func collapseWhitespace(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
  }
}
