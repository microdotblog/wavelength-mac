import AppKit
import SwiftUI

struct ComposeSheet: View {
  let mode: Composer.Mode
  // Set to true to restore the category picker and new-category field.
  private let showsCategories = false
  private let actionLabelMinimumWidth: CGFloat = 56

  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(Toasts.self) private var toasts
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var composer: Composer?
  @State private var showsOptions = false

  var body: some View {
    Group {
      if let composer {
        form(composer)
      } else {
        ProgressView().frame(width: 640, height: 480)
      }
    }
    .onAppear {
      composer = Composer(mode: mode, session: session, library: model.library, posts: model.posts)
    }
    .task(id: composer == nil) {
      guard let composer else { return }
      await composer.loadOptions()

      if composer.isEditing {
        await composer.loadSource()
      }
    }
  }

  private func form(_ composer: Composer) -> some View {
    @Bindable var composer = composer

    return VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          Text(composer.isEditing ? "Edit Post" : "New Post")
            .font(.title2.weight(.bold))

          Spacer()

          Text(session.destinationName)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        if composer.shouldShowTitle {
          TextField("Title", text: $composer.title)
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .padding(10)
            .background(Color.paper, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)) }
        }

        PlainTextEditor(text: $composer.content)
          .frame(minHeight: 220)
          .overlay(alignment: .topLeading) {
            if composer.content.isEmpty {
              Text(composer.isEditing ? "Post text" : "Show notes for this episode…")
                .font(.system(size: PlainTextEditor.fontSize))
                .foregroundStyle(Color.inkSoft)
                .padding(PlainTextEditor.padding)
                .allowsHitTesting(false)
            }
          }
          .background(Color.canvas, in: .rect(cornerRadius: 8))
          .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line) }

        if case .publish(let episodeID) = mode, let episode = model.library.episode(episodeID) {
          EpisodeAttachmentCard(episode: episode, isPublishing: composer.isBusy)
        }

        DisclosureGroup(isExpanded: $showsOptions) {
          options(composer)
            .padding(.top, 8)
        } label: {
          Button {
            withAnimation { showsOptions.toggle() }
          } label: {
            Text("Options")
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
        }

        if let message = composer.errorMessage {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
        }
      }
      .padding(20)

      Divider()

      HStack(spacing: 12) {
        if composer.isBusy {
          ProgressView(value: composer.phase.progress)
            .frame(width: 140)
          Text(composer.phase.label)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button(role: .cancel) {
          dismiss()
        } label: {
          Text("Cancel")
            .frame(minWidth: actionLabelMinimumWidth)
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.bordered)
        .disabled(composer.isBusy)

        Button {
          submit(composer)
        } label: {
          Text(composer.isBusy ? "Posting…" : composer.actionLabel)
            .frame(minWidth: actionLabelMinimumWidth)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .buttonStyle(.borderedProminent)
        .disabled(composer.isBusy || !composer.hasPublishableText)
      }
      .padding(16)
    }
    .frame(width: 660)
    .interactiveDismissDisabled(composer.isBusy)
  }

  private func options(_ composer: Composer) -> some View {
    @Bindable var composer = composer

    return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 14) {
      GridRow {
        Text("Summary").foregroundStyle(.secondary)
        TextField("Optional summary for podcast apps", text: $composer.summary, axis: .vertical)
          .lineLimit(2...4)
      }

      GridRow {
        Text("Status").foregroundStyle(.secondary)
        Picker("Status", selection: $composer.status) {
          Text("Published").tag("published")
          Text("Draft").tag("draft")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
      }

      if showsCategories {
        GridRow {
          Text("Categories").foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 8) {
            if !composer.allCategories.isEmpty {
              FlowLayout {
                ForEach(composer.allCategories, id: \.self) { category in
                  ChipToggle(title: category, isOn: composer.categories.contains(category)) {
                    composer.toggleCategory(category)
                  }
                }
              }
            }

            HStack {
              TextField("New category", text: $composer.newCategory)
                .onSubmit(composer.addNewCategory)
                .frame(maxWidth: 220)
              Button("Add", action: composer.addNewCategory)
                .disabled(composer.newCategory.trimmed.isEmpty)
            }
          }
        }
      }

      if !composer.isEditing, !composer.availableSyndicates.isEmpty {
        GridRow {
          Text("Cross-post").foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 4) {
            ForEach(composer.availableSyndicates) { target in
              Toggle(target.name, isOn: Binding(
                get: { composer.syndicates.contains(target.uid) },
                set: { _ in composer.toggleSyndicate(target.uid) }
              ))
            }
          }
        }
      }
    }
  }

  private func submit(_ composer: Composer) {
    Task {
      if await composer.submit() {
        if composer.isEditing {
          toasts.show("Post updated.")
        } else if composer.status == "draft" {
          toasts.show("Draft saved to Micro.blog.")
        } else {
          toasts.show("Episode published.")
        }
        dismiss()
      }
    }
  }
}

// The Markdown editor is retained separately; the composer currently uses native plain-text editing.
private struct PlainTextEditor: NSViewRepresentable {
  static let fontSize: CGFloat = 18
  static let padding: CGFloat = 13

  @Binding var text: String

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true

    let textView = NSTextView(frame: .zero)
    textView.minSize = .zero
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = .width
    textView.textContainer?.widthTracksTextView = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = .systemFont(ofSize: Self.fontSize)
    textView.textColor = .textColor
    textView.insertionPointColor = .textColor
    textView.textContainerInset = NSSize(width: Self.padding, height: Self.padding)
    textView.textContainer?.lineFragmentPadding = 0
    textView.isContinuousSpellCheckingEnabled = true
    textView.delegate = context.coordinator
    textView.string = text
    textView.setAccessibilityLabel("Show notes")
    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.text = $text
    guard let textView = scrollView.documentView as? NSTextView else { return }

    if textView.string != text {
      textView.string = text
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
    }
  }
}
