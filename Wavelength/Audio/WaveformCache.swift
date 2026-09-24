import Foundation
import Observation

@Observable
final class WaveformCache {
  static let shared = WaveformCache()

  private var detailed: [String: [Float]] = [:]
  @ObservationIgnored private var pending: Set<String> = []

  func levels(for url: URL, clip: ClipMeta) -> [Float] {
    let key = cacheKey(url, clip)

    if let levels = detailed[key] {
      return levels
    }

    load(url, key: key, durationSeconds: clip.durationSeconds)
    return clip.waveform
  }

  private func load(_ url: URL, key: String, durationSeconds: Double) {
    guard !pending.contains(key) else { return }

    pending.insert(key)
    let count = min(2_000, max(Waveform.sampleCount, Int(durationSeconds * 20)))

    Task {
      let levels = (try? await WaveformAnalyzer.levels(of: url, count: count)) ?? []
      pending.remove(key)

      if !levels.isEmpty {
        detailed[key] = levels
      }
    }
  }

  private func cacheKey(_ url: URL, _ clip: ClipMeta) -> String {
    "\(url.path)#\(clip.sizeBytes)#\(clip.durationSeconds)"
  }
}
