import AppKit
import SwiftUI

enum MarkdownFormat {
  case bold
  case italic
  case link
  case quote

  var markers: (before: String, after: String) {
    switch self {
    case .bold: ("**", "**")
    case .italic: ("_", "_")
    case .link: ("[", "](url)")
    case .quote: ("> ", "")
    }
  }
}

@Observable
final class MarkdownEditorProxy {
  @ObservationIgnored weak var textView: NSTextView?

  func apply(_ format: MarkdownFormat) {
    guard let textView else { return }

    let range = textView.selectedRange()
    let text = textView.string as NSString
    let selected = text.substring(with: range)
    let replacement: String

    if format == .quote {
      replacement = selected.isEmpty
        ? format.markers.before
        : selected.components(separatedBy: "\n").map { format.markers.before + $0 }.joined(separator: "\n")
    } else {
      replacement = format.markers.before + selected + format.markers.after
    }

    guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }

    textView.replaceCharacters(in: range, with: replacement)
    textView.didChangeText()

    if format == .link, !selected.isEmpty {
      let urlStart = range.location + (replacement as NSString).length - 4
      textView.setSelectedRange(NSRange(location: urlStart, length: 3))
    } else if selected.isEmpty, format != .quote {
      textView.setSelectedRange(NSRange(location: range.location + (format.markers.before as NSString).length, length: 0))
    } else {
      textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }

    textView.window?.makeFirstResponder(textView)
  }
}

struct MarkdownEditor: NSViewRepresentable {
  @Binding var text: String
  var proxy: MarkdownEditorProxy?
  var placeholder = ""

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true

    guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = MarkdownHighlighter.baseFont
    textView.textColor = .labelColor
    textView.textContainerInset = NSSize(width: 8, height: 10)
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isContinuousSpellCheckingEnabled = true
    textView.string = text
    textView.setAccessibilityLabel(placeholder)
    MarkdownHighlighter.highlight(textView)
    proxy?.textView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }

    proxy?.textView = textView

    if textView.string != text {
      textView.string = text
      MarkdownHighlighter.highlight(textView)
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
      MarkdownHighlighter.highlight(textView)
    }
  }
}

enum MarkdownHighlighter {
  static let baseFont = NSFont.systemFont(ofSize: 14)

  private nonisolated struct Rule {
    let pattern: NSRegularExpression
    let attributes: [NSAttributedString.Key: Any]
    var group = 0
  }

  nonisolated(unsafe) private static let rules: [Rule] = {
    let accent = NSColor(named: "AccentColor") ?? .systemOrange
    let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let bold = NSFont.systemFont(ofSize: 14, weight: .bold)
    let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask)
    let heading = NSFont.systemFont(ofSize: 16, weight: .bold)

    func rule(_ pattern: String, _ attributes: [NSAttributedString.Key: Any], options: NSRegularExpression.Options = [], group: Int = 0) -> Rule {
      Rule(pattern: try! NSRegularExpression(pattern: pattern, options: options), attributes: attributes, group: group)
    }

    return [
      rule("</?[a-zA-Z][a-zA-Z0-9-]*[^>]*>", [.foregroundColor: NSColor.secondaryLabelColor]),
      rule("\\*\\*(.*?)\\*\\*", [.font: bold]),
      rule("(^|[^\\w<>])(_[^_\\r\\n()]+_)", [.font: italic], group: 2),
      rule("\\[([^\\]\\r\\n]+)\\]", [.foregroundColor: accent]),
      rule("\\]\\(([^\\)\\r\\n]*)\\)", [.foregroundColor: NSColor.secondaryLabelColor]),
      rule("\\bhttps?://[^\\s<()]+", [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue]),
      rule("^>.*$", [.foregroundColor: NSColor.secondaryLabelColor, .font: italic], options: .anchorsMatchLines),
      rule("^#+ .*$", [.font: heading], options: .anchorsMatchLines),
      rule("-{3,}", [.foregroundColor: NSColor.tertiaryLabelColor]),
      rule("(?<![\\w])@[a-zA-Z0-9_]+(?:\\.[a-zA-Z]+)*", [.foregroundColor: accent]),
      rule("`[^`\\r\\n]+`", [.font: mono, .backgroundColor: NSColor.quaternaryLabelColor]),
      rule("```[\\s\\S]*?```", [.font: mono, .backgroundColor: NSColor.quaternaryLabelColor]),
    ]
  }()

  static func highlight(_ textView: NSTextView) {
    guard let storage = textView.textStorage else { return }

    let text = storage.string
    let full = NSRange(location: 0, length: (text as NSString).length)

    storage.beginEditing()
    storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: full)

    for rule in rules {
      rule.pattern.enumerateMatches(in: text, range: full) { match, _, _ in
        guard let match else { return }
        let range = match.range(at: rule.group)

        if range.location != NSNotFound {
          storage.addAttributes(rule.attributes, range: range)
        }
      }
    }

    storage.endEditing()
    textView.typingAttributes = [.font: baseFont, .foregroundColor: NSColor.labelColor]
  }
}
