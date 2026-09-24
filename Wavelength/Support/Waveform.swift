import Foundation

nonisolated enum Waveform {
  static let sampleCount = 128
  static let silenceFloorDecibels: Float = -60

  static func clamp(_ value: Float) -> Float {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }

  static func normalize(decibels: Float) -> Float {
    guard decibels.isFinite else { return 0 }
    let clamped = min(max(decibels, silenceFloorDecibels), 0)
    return (clamped - silenceFloorDecibels) / -silenceFloorDecibels
  }

  static func normalize(rms: Float) -> Float {
    guard rms > 0 else { return 0 }
    return normalize(decibels: 20 * log10(rms))
  }

  static func downsample(_ samples: [Float], to targetCount: Int = sampleCount) -> [Float] {
    let count = max(1, targetCount)
    let safe = samples.filter(\.isFinite)

    if safe.isEmpty {
      return []
    }

    if safe.count <= count {
      return safe.map(clamp)
    }

    let bucketSize = Double(safe.count) / Double(count)

    return (0..<count).map { index in
      let start = Int(Double(index) * bucketSize)
      let end = max(start + 1, Int(Double(index + 1) * bucketSize))
      return safe[start..<min(end, safe.count)].map(clamp).max() ?? 0
    }
  }

  static func resample(_ waveform: [Float], to targetCount: Int) -> [Float] {
    let count = max(1, targetCount)
    let safe = waveform.map(clamp)

    if safe.isEmpty {
      return []
    }

    if safe.count == 1 || count == 1 {
      return Array(repeating: safe[0], count: count)
    }

    if safe.count >= count {
      return downsample(safe, to: count)
    }

    let lastIndex = safe.count - 1

    return (0..<count).map { index in
      let position = Double(index) / Double(count - 1) * Double(lastIndex)
      let lower = Int(position)
      let upper = min(lower + 1, lastIndex)
      let mix = Float(position - Double(lower))
      return clamp(safe[lower] * (1 - mix) + safe[upper] * mix)
    }
  }

  static func merge(_ clips: [ClipMeta], to targetCount: Int = sampleCount) -> [Float] {
    let count = max(1, targetCount)
    let total = clips.reduce(0) { $0 + max($1.durationSeconds, 0) }

    guard !clips.isEmpty, total > 0 else { return [] }

    var peaks = Array(repeating: Float(0), count: count)
    var elapsed = 0.0

    for clip in clips {
      let duration = max(clip.durationSeconds, 0)

      guard duration > 0 else { continue }

      let startBucket = Int((elapsed / total * Double(count)).rounded(.down))
      let endBucket = min(count, max(startBucket + 1, Int(((elapsed + duration) / total * Double(count)).rounded(.up))))
      let span = endBucket - startBucket

      for bucket in startBucket..<endBucket {
        let fraction = span > 0 ? Double(bucket - startBucket) / Double(span) : 0
        let value = sample(clip.waveform, at: fraction)
        peaks[bucket] = max(peaks[bucket], value)
      }

      elapsed += duration
    }

    return peaks
  }

  static func slice(_ waveform: [Float], from startFraction: Double, to endFraction: Double) -> [Float] {
    guard !waveform.isEmpty else { return [] }

    let start = min(max(startFraction, 0), 1)
    let end = min(max(endFraction, start), 1)
    let startIndex = min(Int(start * Double(waveform.count)), waveform.count - 1)
    let endIndex = min(waveform.count, max(startIndex + 1, Int((end * Double(waveform.count)).rounded(.up))))

    return waveform[startIndex..<endIndex].map(clamp)
  }

  private static func sample(_ waveform: [Float], at fraction: Double) -> Float {
    guard !waveform.isEmpty else { return 0 }
    let index = min(waveform.count - 1, Int(fraction * Double(waveform.count)))
    return clamp(waveform[index])
  }
}
