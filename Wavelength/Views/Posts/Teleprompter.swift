import SwiftUI
import WebKit

struct Teleprompter: View {
  let title: String
  let content: String
  var fontSize = 20

  @Environment(\.colorScheme) private var colorScheme

  private var html: String {
    NarrateHTML.build(
      title: title,
      content: content,
      palette: colorScheme == .dark ? .dark : .light,
      fontSize: fontSize
    )
  }

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        SwiftUITeleprompterWebView(html: html)
      } else {
        AppKitTeleprompterWebView(html: html)
      }
    }
    .accessibilityLabel("Post text")
  }
}

@available(macOS 26.0, *)
private struct SwiftUITeleprompterWebView: View {
  let html: String
  @State private var page = WebPage(navigationDecider: ExternalLinkDecider())

  var body: some View {
    WebView(page)
      .task(id: html) {
        _ = page.load(html: html)
      }
  }
}

@available(macOS 26.0, *)
private struct ExternalLinkDecider: WebPage.NavigationDeciding {
  func decidePolicy(
    for action: WebPage.NavigationAction,
    preferences: inout WebPage.NavigationPreferences
  ) async -> WKNavigationActionPolicy {
    policyForTeleprompterNavigation(action.navigationType, url: action.request.url)
  }
}

private struct AppKitTeleprompterWebView: NSViewRepresentable {
  let html: String

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> WKWebView {
    let view = WKWebView()
    view.navigationDelegate = context.coordinator
    return view
  }

  func updateNSView(_ view: WKWebView, context: Context) {
    guard context.coordinator.loadedHTML != html else { return }

    context.coordinator.loadedHTML = html
    view.loadHTMLString(html, baseURL: nil)
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var loadedHTML: String?

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
      policyForTeleprompterNavigation(action.navigationType, url: action.request.url)
    }
  }
}

private func policyForTeleprompterNavigation(_ type: WKNavigationType, url: URL?) -> WKNavigationActionPolicy {
  guard type == .linkActivated, let url else { return .allow }

  NSWorkspace.shared.open(url)
  return .cancel
}
