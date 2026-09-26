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

    if let focused = textView.window?.firstResponder as? NSTextView, focused !== textView {
      return
    }

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
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true

    let textView = MarkdownTextView(frame: .zero)
    textView.minSize = .zero
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = .width
    textView.textContainer?.widthTracksTextView = true
    scrollView.documentView = textView

    textView.delegate = context.coordinator
    textView.textStorage?.delegate = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = MarkdownStyle.baseFont
    textView.textColor = MarkdownStyle.text
    textView.insertionPointColor = MarkdownStyle.caret
    textView.defaultParagraphStyle = MarkdownStyle.paragraph
    textView.typingAttributes = MarkdownStyle.baseAttributes
    textView.textContainerInset = NSSize(width: MarkdownStyle.padding, height: MarkdownStyle.padding)
    textView.textContainer?.lineFragmentPadding = 0
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isContinuousSpellCheckingEnabled = true
    context.coordinator.textView = textView
    textView.string = text
    textView.setAccessibilityLabel(placeholder)
    proxy?.textView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }

    proxy?.textView = textView

    if textView.string != text {
      textView.string = text
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    var text: Binding<String>
    weak var textView: NSTextView?

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }

    func textStorage(
      _ textStorage: NSTextStorage,
      didProcessEditing editedMask: NSTextStorageEditActions,
      range editedRange: NSRange,
      changeInLength delta: Int
    ) {
      guard editedMask.contains(.editedCharacters), textView?.hasMarkedText() != true else { return }
      MarkdownStyle.apply(to: textStorage)
    }
  }
}

final class MarkdownTextView: NSTextView {
  override func keyDown(with event: NSEvent) {
    let isReturn = event.keyCode == 36 || event.keyCode == 76

    if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift, !hasMarkedText() {
      insertLineBreak(nil)
    } else {
      super.keyDown(with: event)
    }
  }

  override func insertNewline(_ sender: Any?) {
    let range = selectedRange()
    let before = (string as NSString).substring(to: range.location)
    insertText(MarkdownReturn.newline(after: before), replacementRange: range)
  }

  override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
    insertLineBreak(sender)
  }

  override func insertLineBreak(_ sender: Any?) {
    insertText("\n", replacementRange: selectedRange())
  }

  override func paste(_ sender: Any?) {
    let range = selectedRange()

    if range.length > 0,
       let pasted = NSPasteboard.general.string(forType: .string),
       let link = MarkdownPaste.link(wrapping: (string as NSString).substring(with: range), in: pasted) {
      insertText(link, replacementRange: range)
    } else {
      super.paste(sender)
    }
  }
}

nonisolated enum MarkdownReturn {
  static func newline(after text: String) -> String {
    guard !text.isEmpty, !text.hasSuffix("\n") else { return "\n" }
    let fences = text.components(separatedBy: "```").count - 1
    return fences % 2 == 1 ? "\n" : "\n\n"
  }
}

nonisolated enum MarkdownPaste {
  static func link(wrapping selection: String, in pasted: String) -> String? {
    guard let url = webURL(pasted), !selection.isEmpty, webURL(selection) == nil else { return nil }
    return "[\(selection)](\(url))"
  }

  private static func webURL(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.contains(where: \.isWhitespace),
          let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
          components.host?.isEmpty == false else {
      return nil
    }

    return trimmed
  }
}

nonisolated enum MarkdownHighlighter {
  enum Style: Equatable {
    case bold
    case italic
    case linkText
    case linkURL
    case quote
    case tag
    case attributeName
    case attributeValue
    case code
    case header
    case divider
    case username
  }

  struct Span: Equatable {
    let range: NSRange
    let style: Style
  }

  static let maximumLength = 5_000

  private struct Rule {
    let pattern: NSRegularExpression
    let styles: [(group: Int, style: Style)]
  }

  private static let urlPattern = regex(#"\bhttps?://[^\s<()]+(?:\([^\s<()]*\)[^\s<()]*)*"#)

  private static let rules: [Rule] = [
    Rule(pattern: regex(#"(</?[a-zA-Z][a-zA-Z0-9-]*)(?=[\s>])"#), styles: [(1, .tag)]),
    Rule(pattern: regex(#"(?<![a-zA-Z:-])([a-zA-Z:-]+)=("[^"&<>]*?")"#), styles: [(1, .attributeName), (2, .attributeValue)]),
    Rule(pattern: regex(#"```[\s\S]*?```"#), styles: [(0, .code)]),
    Rule(pattern: regex(#"(?:^|[^`])(`[^`\r\n]+`)(?!`)"#), styles: [(1, .code)]),
    Rule(pattern: regex(#"\*\*(.*?)\*\*"#), styles: [(0, .bold)]),
    Rule(pattern: regex(#"(?:^|\W)(_[^_\r\n()]+_)"#), styles: [(1, .italic)]),
    Rule(pattern: regex(#"(\[[^\]\r\n]+\])(\([^\)\r\n]*\))"#), styles: [(1, .linkText), (2, .linkURL)]),
    Rule(pattern: regex(#"^>.*"#, options: .anchorsMatchLines), styles: [(0, .quote)]),
    Rule(pattern: regex(#"^#+ .*$"#, options: .anchorsMatchLines), styles: [(0, .header)]),
    Rule(pattern: regex(#"-{3,}"#), styles: [(0, .divider)]),
    Rule(pattern: regex(#"@[a-zA-Z0-9@_]+(?:\.[a-zA-Z]+)*"#), styles: [(0, .username)]),
  ]

  static func spans(in text: String) -> [Span] {
    let length = (text as NSString).length
    guard length > 0, length <= maximumLength else { return [] }

    let masked = maskingURLs(in: text)
    let full = NSRange(location: 0, length: length)
    var spans: [Span] = []

    for rule in rules {
      rule.pattern.enumerateMatches(in: masked, range: full) { match, _, _ in
        guard let match else { return }

        for (group, style) in rule.styles {
          let range = match.range(at: group)

          if range.location != NSNotFound, range.length > 0 {
            spans.append(Span(range: range, style: style))
          }
        }
      }
    }

    return spans
  }

  private static func maskingURLs(in text: String) -> String {
    let masked = NSMutableString(string: text)
    let full = NSRange(location: 0, length: masked.length)

    for match in urlPattern.matches(in: text, range: full).reversed() {
      masked.replaceCharacters(in: match.range, with: String(repeating: "x", count: match.range.length))
    }

    return masked as String
  }

  private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: options)
  }
}

enum MarkdownStyle {
  static let fontSize: CGFloat = 18
  static let padding: CGFloat = 13

  static let baseFont = font(bold: false, italic: false, code: false)

  static let text = NSColor(light: 0x24180D, dark: 0xFFF7E8)
  static let caret = NSColor(named: "AccentColor") ?? .systemOrange
  static let link = NSColor(light: 0x337AB7, dark: 0x337AB7)
  static let muted = NSColor(light: 0x808080, dark: 0x808080)
  static let quote = NSColor(light: 0x2F7D32, dark: 0x78B855)
  static let tag = NSColor(light: 0x96268A, dark: 0xE3ABED)
  static let codeBackground = NSColor(light: 0xFFF3D2, dark: 0x2D2115)

  static let paragraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    let natural = NSLayoutManager().defaultLineHeight(for: baseFont)
    style.lineSpacing = max(fontSize * 1.35 - natural, 0)
    return style
  }()

  static var baseAttributes: [NSAttributedString.Key: Any] {
    [.font: baseFont, .foregroundColor: text, .paragraphStyle: paragraph]
  }

  static func attributes(for style: MarkdownHighlighter.Style) -> [NSAttributedString.Key: Any] {
    switch style {
    case .bold, .header, .italic: [:]
    case .linkText: [.foregroundColor: link, .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .linkURL, .attributeName, .divider: [.foregroundColor: muted]
    case .quote: [.foregroundColor: quote]
    case .tag: [.foregroundColor: tag]
    case .attributeValue, .username: [.foregroundColor: link]
    case .code: [.backgroundColor: codeBackground]
    }
  }

  static func font(bold: Bool, italic: Bool, code: Bool) -> NSFont {
    let weight: NSFont.Weight = bold ? .bold : .regular
    let font = code ? NSFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: weight) : NSFont.systemFont(ofSize: fontSize, weight: weight)
    return italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
  }

  static func apply(to storage: NSTextStorage) {
    let length = storage.length
    let full = NSRange(location: 0, length: length)
    var traits = [UInt8](repeating: 0, count: length)
    storage.setAttributes(baseAttributes, range: full)

    for span in MarkdownHighlighter.spans(in: storage.string) where NSMaxRange(span.range) <= length {
      storage.addAttributes(attributes(for: span.style), range: span.range)

      let trait: UInt8 = switch span.style {
      case .bold, .header: 1
      case .italic: 2
      case .code: 4
      default: 0
      }

      if trait != 0 {
        for index in span.range.location..<NSMaxRange(span.range) {
          traits[index] |= trait
        }
      }
    }

    var start = 0

    while start < length {
      var end = start + 1

      while end < length, traits[end] == traits[start] {
        end += 1
      }

      if traits[start] != 0 {
        let trait = traits[start]
        storage.addAttribute(.font, value: font(bold: trait & 1 != 0, italic: trait & 2 != 0, code: trait & 4 != 0), range: NSRange(location: start, length: end - start))
      }

      start = end
    }
  }
}
