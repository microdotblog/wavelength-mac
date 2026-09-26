import Foundation

nonisolated enum SegmentCarving {
  enum Edit {
    case delete
    case split
  }

  struct Span {
    let name: String
    let start: Double
    let duration: Double
  }

  static let minimumPiece = 0.05

  static func plan(_ edit: Edit, range: ClosedRange<Double>, spans: [Span]) -> [String: [Range<Double>]] {
    var plan: [String: [Range<Double>]] = [:]

    for span in spans {
      let start = min(max(range.lowerBound - span.start, 0), span.duration)
      let end = min(max(range.upperBound - span.start, 0), span.duration)
      guard end - start >= minimumPiece else { continue }

      let cuts = [start, end].filter { $0 >= minimumPiece && $0 <= span.duration - minimumPiece }
      let bounds = [0] + cuts + [span.duration]
      let pieces = zip(bounds, bounds.dropFirst()).map { $0..<$1 }

      switch edit {
      case .delete:
        plan[span.name] = pieces.filter { $0.upperBound <= start + 0.0001 || $0.lowerBound >= end - 0.0001 }
      case .split:
        if pieces.count > 1 {
          plan[span.name] = pieces
        }
      }
    }

    return plan
  }
}
