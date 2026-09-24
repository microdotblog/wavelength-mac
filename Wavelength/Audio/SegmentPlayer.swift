import AVFoundation
import Observation

@Observable
final class SegmentPlayer {
  private(set) var isPlaying = false
  private(set) var currentTime: Double = 0
  private(set) var duration: Double = 0
  private(set) var boundaries: [Double] = []
  private(set) var isLoading = false

  @ObservationIgnored private let player = AVPlayer()
  @ObservationIgnored private var sources: [URL] = []
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  @ObservationIgnored private var loadGeneration = 0

  init() {
    player.actionAtItemEnd = .pause

    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.04, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      MainActor.assumeIsolated {
        self?.tick(time)
      }
    }

    observers.append(NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let sender = (notification.object as AnyObject?).map(ObjectIdentifier.init)
      MainActor.assumeIsolated {
        guard let self, let item = self.player.currentItem, sender == ObjectIdentifier(item) else { return }
        self.isPlaying = false
        self.currentTime = self.duration
      }
    })

    for name in [Notification.Name.wavelengthWillPlay, .wavelengthWillRecord] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
        let sender = (notification.object as AnyObject?).map(ObjectIdentifier.init)
        MainActor.assumeIsolated {
          guard let self, sender != ObjectIdentifier(self) else { return }
          self.pause()
        }
      })
    }
  }

  isolated deinit {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }

    observers.forEach(NotificationCenter.default.removeObserver)
    player.pause()
  }

  var progress: Double {
    duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
  }

  var currentSegmentIndex: Int? {
    guard !boundaries.isEmpty else { return nil }
    return boundaries.lastIndex { $0 <= currentTime + 0.0001 }
  }

  func segmentStart(_ index: Int) -> Double {
    boundaries.indices.contains(index) ? boundaries[index] : 0
  }

  func load(_ urls: [URL]) async {
    guard urls != sources else { return }

    loadGeneration += 1
    let generation = loadGeneration
    let resumeAt = currentTime
    sources = urls
    pause()

    guard !urls.isEmpty else {
      player.replaceCurrentItem(with: nil)
      boundaries = []
      duration = 0
      currentTime = 0
      return
    }

    isLoading = true
    defer {
      if generation == loadGeneration {
        isLoading = false
      }
    }

    do {
      let item: AVPlayerItem
      var starts: [Double] = []

      if urls.count == 1 {
        let asset = AVURLAsset(url: urls[0])
        item = AVPlayerItem(asset: asset)
        starts = [0]
      } else {
        let composition = try await AudioEditing.composition(of: urls)
        var cursor = 0.0

        for url in urls {
          starts.append(cursor)
          cursor += try await AVURLAsset(url: url).load(.duration).seconds
        }

        item = AVPlayerItem(asset: composition)
      }

      let total = try await item.asset.load(.duration).seconds

      guard generation == loadGeneration else { return }

      player.replaceCurrentItem(with: item)
      boundaries = starts
      duration = total.isFinite ? total : 0
      seek(to: min(resumeAt, duration))
    } catch {
      guard generation == loadGeneration else { return }
      player.replaceCurrentItem(with: nil)
      boundaries = []
      duration = 0
    }
  }

  func reset() {
    sources = []
    loadGeneration += 1
    pause()
    player.replaceCurrentItem(with: nil)
    boundaries = []
    duration = 0
    currentTime = 0
  }

  func toggle() {
    isPlaying ? pause() : play()
  }

  func play() {
    guard player.currentItem != nil else { return }

    if duration > 0, currentTime >= duration - 0.05 {
      seek(to: 0)
    }

    NotificationCenter.default.post(name: .wavelengthWillPlay, object: self)
    player.play()
    isPlaying = true
  }

  func pause() {
    player.pause()
    isPlaying = false
  }

  func seek(to seconds: Double) {
    let target = min(max(seconds, 0), max(duration, 0))
    currentTime = target
    player.seek(to: CMTime(seconds: target, preferredTimescale: 44_100), toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func seek(fraction: Double) {
    seek(to: fraction * duration)
  }

  func skip(by seconds: Double) {
    seek(to: currentTime + seconds)
  }

  func play(segment index: Int) {
    seek(to: segmentStart(index))
    play()
  }

  private func tick(_ time: CMTime) {
    guard isPlaying else { return }
    let seconds = time.seconds
    currentTime = seconds.isFinite ? seconds : 0
  }
}
