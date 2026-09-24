import AVFoundation
import AppKit
import MediaPlayer
import Observation

@Observable
final class NowPlaying {
  private(set) var post: DiscoverPost?
  private(set) var isPlaying = false
  private(set) var isBuffering = false
  private(set) var currentTime: Double = 0
  private(set) var duration: Double = 0
  var rate: Float = 1 {
    didSet {
      if isPlaying {
        player.rate = rate
      }
      updateNowPlayingInfo()
    }
  }

  @ObservationIgnored private let player = AVPlayer()
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  @ObservationIgnored private var statusObservation: NSKeyValueObservation?
  @ObservationIgnored private var artwork: MPMediaItemArtwork?

  static let rates: [Float] = [1, 1.25, 1.5, 1.75, 2]

  init() {
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
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
        self.player.seek(to: .zero)
        self.currentTime = 0
        self.updateNowPlayingInfo()
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

    configureRemoteCommands()
  }

  var progress: Double {
    duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
  }

  func isCurrent(_ post: DiscoverPost) -> Bool {
    self.post?.id == post.id
  }

  func toggle(_ post: DiscoverPost) {
    if isCurrent(post) {
      toggle()
    } else {
      play(post)
    }
  }

  func play(_ post: DiscoverPost) {
    guard let url = post.audioURL else { return }

    if !isCurrent(post) {
      self.post = post
      currentTime = 0
      duration = Double(post.durationSeconds)
      artwork = nil
      let item = AVPlayerItem(url: url)
      statusObservation = item.observe(\.status) { [weak self] item, _ in
        Task { @MainActor in
          self?.itemStatusChanged()
        }
      }
      player.replaceCurrentItem(with: item)
      loadArtwork(for: post)
    }

    resume()
  }

  func toggle() {
    isPlaying ? pause() : resume()
  }

  func resume() {
    guard player.currentItem != nil else { return }
    NotificationCenter.default.post(name: .wavelengthWillPlay, object: self)
    player.playImmediately(atRate: rate)
    isPlaying = true
    updateNowPlayingInfo()
  }

  func pause() {
    guard isPlaying else { return }
    player.pause()
    isPlaying = false
    updateNowPlayingInfo()
  }

  func seek(fraction: Double) {
    seek(to: fraction * duration)
  }

  func seek(to seconds: Double) {
    let target = min(max(seconds, 0), max(duration, 0))
    currentTime = target
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    updateNowPlayingInfo()
  }

  func skip(by seconds: Double) {
    seek(to: currentTime + seconds)
  }

  func stop() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    post = nil
    isPlaying = false
    currentTime = 0
    duration = 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

  private func tick(_ time: CMTime) {
    let seconds = time.seconds

    if seconds.isFinite {
      currentTime = seconds
    }

    isBuffering = isPlaying && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
  }

  private func itemStatusChanged() {
    guard let item = player.currentItem, item.status == .readyToPlay else { return }

    let seconds = item.duration.seconds

    if seconds.isFinite, seconds > 0 {
      duration = seconds
    }

    updateNowPlayingInfo()
  }

  private func loadArtwork(for post: DiscoverPost) {
    guard let url = post.artworkURL else { return }

    Task {
      guard let (data, _) = try? await HTTP.session.data(from: url),
            let image = NSImage(data: data),
            self.post?.id == post.id else {
        return
      }

      artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      updateNowPlayingInfo()
    }
  }

  private func updateNowPlayingInfo() {
    guard let post else { return }

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: post.displayTitle,
      MPMediaItemPropertyArtist: post.sourceLabel,
      MPMediaItemPropertyAlbumTitle: "Discover",
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]

    if let artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
  }

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.skipForwardCommand.preferredIntervals = [30]
    center.skipBackwardCommand.preferredIntervals = [15]

    center.playCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.resume() }
      return .success
    }

    center.pauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.pause() }
      return .success
    }

    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.toggle() }
      return .success
    }

    center.skipForwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(by: 30) }
      return .success
    }

    center.skipBackwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(by: -15) }
      return .success
    }

    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let position = event.positionTime
      MainActor.assumeIsolated { self?.seek(to: position) }
      return .success
    }
  }
}
