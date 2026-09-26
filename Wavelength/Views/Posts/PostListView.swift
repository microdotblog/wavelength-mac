import SwiftUI

struct PostListView: View {
  enum Source {
    case all
    case narrations
  }

  let source: Source

  @Environment(AppModel.self) private var model
  @Environment(PostsStore.self) private var posts
  @Environment(Session.self) private var session
  @Environment(\.openURL) private var openURL
  @State private var pendingDelete: Post?

  private var visiblePosts: [Post] {
    switch source {
    case .all: posts.filteredPosts
    case .narrations: posts.narratedPosts
    }
  }

  var body: some View {
    @Bindable var model = model
    @Bindable var posts = posts

    Group {
      if visiblePosts.isEmpty {
        if posts.isLoading || !posts.didHydrate {
          ProgressView()
        } else if let message = posts.errorMessage {
          EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn’t Load Posts", message: message, actionTitle: "Try Again") {
            Task { await posts.refresh() }
          }
        } else {
          emptyState
        }
      } else {
        List(selection: $model.selectedPostUID) {
          ForEach(visiblePosts) { post in
            PostRow(post: post)
              .tag(post.uid)
              .contextMenu { menu(for: post) }
          }
        }
        .onDeleteCommand {
          pendingDelete = posts.post(model.selectedPostUID)
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if source == .all && posts.filter != .all {
        filterBar
      }
    }
    .navigationTitle(source == .all ? "Posts" : "Narrations")
    .navigationSubtitle(session.destinationName)
    .toolbar {
      if source == .all {
        ToolbarItem(placement: .navigation) {
          Menu {
            Picker("Filter", selection: $posts.filter) {
              ForEach(PostsStore.Filter.allCases) { filter in
                Text(filter.label).tag(filter)
              }
            }
            .pickerStyle(.inline)
            .labelsHidden()
          } label: {
            Label("Filter", systemImage: posts.filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
          }
          .help("Filter posts")
        }
      }

      ToolbarItem {
        Button {
          Task { await posts.refresh() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(posts.isLoading)
      }
    }
    .task {
      if !posts.didHydrate {
        await posts.refresh()
      }
    }
    .confirmationDialog(
      "Delete this post?",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      presenting: pendingDelete
    ) { post in
      Button("Delete Post", role: .destructive) {
        Task { await model.delete(post: post.uid) }
      }
    } message: { _ in
      Text("This deletes the post from Micro.blog.")
    }
  }

  private var filterBar: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Showing: \(posts.filter.label)")
          .font(.callout)
          .foregroundStyle(.secondary)

        Spacer()

        Button { posts.filter = .all } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Show all posts")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 6)

      Divider()
    }
    .background(.bar)
  }

  @ViewBuilder
  private var emptyState: some View {
    switch source {
    case .all:
      EmptyStateView(symbol: "text.bubble", title: posts.filter.emptyTitle, message: "Your Micro.blog posts will show up here.")
    case .narrations:
      EmptyStateView(
        symbol: "mic",
        title: "No narrations yet",
        message: "Posts with a hidden audio narration will show up here. Pick a post in Posts and record yourself reading it."
      )
    }
  }

  @ViewBuilder
  private func menu(for post: Post) -> some View {
    Button("Narrate", systemImage: "mic") { model.select(post: post.uid, in: source == .all ? .posts : .narrations) }
    Button("Edit Post…", systemImage: "square.and.pencil") { model.sheet = .editPost(postUID: post.uid) }

    if let url = URL(string: post.url) {
      Button("Open in Browser", systemImage: "safari") { openURL(url) }
      Button("Copy Link", systemImage: "link") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
      }
    }

    if post.kind == .narrated {
      Button("Delete Narration…", systemImage: "waveform.slash", role: .destructive) {
        Task { await model.removeNarration(from: post.uid) }
      }
    }

    Divider()
    Button("Delete Post…", systemImage: "trash", role: .destructive) { pendingDelete = post }
  }
}

struct PostRow: View {
  let post: Post

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(post.displayTitle)
          .font(.body.weight(.semibold))
          .lineLimit(1)

        Spacer(minLength: 8)

        if post.kind != .post {
          Image(systemName: post.kind.symbol)
            .foregroundStyle(Color.accentColor)
            .help(post.kind.label)
        }
      }

      if !post.displaySummary.isEmpty {
        Text(post.displaySummary)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      if let date = post.publishedDate {
        Text(date.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 4)
  }
}
