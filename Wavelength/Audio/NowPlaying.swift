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
      statusObservation = Self.observeStatus(of: item) { [weak self] in
        self?.itemStatusChanged()
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
            let size = NSImage(data: data)?.size,
            self.post?.id == post.id else {
        return
      }

      artwork = Self.artwork(from: data, size: size)
      updateNowPlayingInfo()
    }
  }

  nonisolated static func artwork(from data: Data, size: CGSize) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: size) { _ in
      NSImage(data: data) ?? NSImage(size: size)
    }
  }

  nonisolated private static func observeStatus(
    of item: AVPlayerItem,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> NSKeyValueObservation {
    item.observe(\.status) { _, _ in
      Task { @MainActor in onChange() }
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

    Self.handle(center.playCommand) { [weak self] in self?.resume() }
    Self.handle(center.pauseCommand) { [weak self] in self?.pause() }
    Self.handle(center.togglePlayPauseCommand) { [weak self] in self?.toggle() }
    Self.handle(center.skipForwardCommand) { [weak self] in self?.skip(by: 30) }
    Self.handle(center.skipBackwardCommand) { [weak self] in self?.skip(by: -15) }
    Self.handleSeek(center.changePlaybackPositionCommand) { [weak self] position in self?.seek(to: position) }
  }

  nonisolated private static func handle(_ command: MPRemoteCommand, action: @escaping @MainActor @Sendable () -> Void) {
    command.addTarget { _ in
      Task { @MainActor in action() }
      return .success
    }
  }

  nonisolated private static func handleSeek(
    _ command: MPChangePlaybackPositionCommand,
    action: @escaping @MainActor @Sendable (TimeInterval) -> Void
  ) {
    command.addTarget { event in
      guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
        return .commandFailed
      }

      Task { @MainActor in action(position) }
      return .success
    }
  }
}
