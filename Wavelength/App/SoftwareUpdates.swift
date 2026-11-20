import Combine
import Foundation
import Observation
import Sparkle

@Observable
final class SoftwareUpdates {
  private(set) var canCheckForUpdates = false
  @ObservationIgnored private var controller: SPUStandardUpdaterController?
  @ObservationIgnored private var availability: AnyCancellable?

  func start() {
    guard controller == nil,
          let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
          let url = URL(string: feed), url.scheme == "https", url.host != nil,
          let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
          Data(base64Encoded: key)?.count == 32 else { return }

    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    self.controller = controller
    availability = controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] available in
      self?.canCheckForUpdates = available
    }
  }

  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    controller?.checkForUpdates(nil)
  }
}
