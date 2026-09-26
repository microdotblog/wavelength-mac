import SwiftUI

struct ComposeSheet: View {
  let mode: Composer.Mode

  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(Toasts.self) private var toasts
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var composer: Composer?
  @State private var editorProxy = MarkdownEditorProxy()
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

          Label(session.destinationName, systemImage: "globe")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        if composer.shouldShowTitle {
          TextField("Title", text: $composer.title)
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .padding(10)
            .background(Color.paper, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line) }
        }

        VStack(spacing: 0) {
          HStack(spacing: 2) {
            formatButton("bold", .bold, "Bold")
            formatButton("italic", .italic, "Italic")
            formatButton("link", .link, "Link")
            formatButton("text.quote", .quote, "Quote")

            Divider().frame(height: 16).padding(.horizontal, 6)

            if !composer.shouldShowTitle {
              Button("Add Title") { composer.showsTitle = true }
                .buttonStyle(.borderless)
                .font(.callout)
            }

            Spacer()

            Text("\(composer.content.count)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(composer.content.count > Composer.shortPostLength ? Color.accentColor : .secondary)
              .help("Posts longer than \(Composer.shortPostLength) characters get a title on Micro.blog.")
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)

          Divider()

          MarkdownEditor(text: $composer.content, proxy: editorProxy, placeholder: "Show notes")
            .frame(minHeight: 220)
            .overlay(alignment: .topLeading) {
              if composer.content.isEmpty {
                Text(composer.isEditing ? "Post text" : "Show notes for this episode…")
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 13)
                  .padding(.vertical, 10)
                  .allowsHitTesting(false)
              }
            }
        }
        .background(Color.paper, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line) }

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

        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(composer.isBusy)

        Button(composer.isBusy ? "Posting…" : composer.actionLabel) {
          submit(composer)
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

  private func formatButton(_ symbol: String, _ format: MarkdownFormat, _ help: String) -> some View {
    Button {
      editorProxy.apply(format)
    } label: {
      Image(systemName: symbol)
        .frame(width: 24, height: 20)
    }
    .buttonStyle(.borderless)
    .help(help)
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
