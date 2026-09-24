import SwiftUI
import WebKit

struct Teleprompter: View {
  let title: String
  let content: String
  var fontSize = 20

  @Environment(\.colorScheme) private var colorScheme
  @State private var page = WebPage(navigationDecider: ExternalLinkDecider())

  private var html: String {
    NarrateHTML.build(
      title: title,
      content: content,
      palette: colorScheme == .dark ? .dark : .light,
      fontSize: fontSize
    )
  }

  var body: some View {
    WebView(page)
      .task(id: html) {
        _ = page.load(html: html)
      }
      .accessibilityLabel("Post text")
  }
}

private struct ExternalLinkDecider: WebPage.NavigationDeciding {
  func decidePolicy(
    for action: WebPage.NavigationAction,
    preferences: inout WebPage.NavigationPreferences
  ) async -> WKNavigationActionPolicy {
    guard action.navigationType == .linkActivated, let url = action.request.url else {
      return .allow
    }

    NSWorkspace.shared.open(url)
    return .cancel
  }
}
