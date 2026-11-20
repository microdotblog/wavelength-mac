import SwiftUI

struct RootView: View {
  @Environment(Session.self) private var session

  var body: some View {
    Group {
      if !session.isHydrated {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if session.isSignedIn {
        MainView()
      } else {
        Color.clear
      }
    }
    .overlay { ToastOverlay() }
  }
}

private struct MainView: View {
  private let sidebarWidthRange: ClosedRange<CGFloat> = 190...280

  @Environment(AppModel.self) private var model
  @Environment(Library.self) private var library
  @Environment(PostsStore.self) private var posts
  @State private var columns = NavigationSplitViewVisibility.all
  @State private var sidebarWidth: CGFloat = 210

  private var showsListInDetail: Bool {
    switch model.sidebar {
    case .podcasts: library.episodes.isEmpty
    case .narrations: posts.narratedPosts.isEmpty
    default: false
    }
  }

  var body: some View {
    @Bindable var model = model

    Group {
      if showsListInDetail {
        NavigationSplitView(columnVisibility: $columns) {
          sidebar
        } detail: {
          detail
        }
      } else {
        NavigationSplitView(columnVisibility: $columns) {
          sidebar
        } content: {
          content
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
        } detail: {
          detail
        }
      }
    }
    .sheet(item: $model.sheet) { sheet in
      switch sheet {
      case .recording(let title, let autoStart, let onFinish):
        RecordingCardView(title: title, autoStart: autoStart, onFinish: onFinish)
      case .publish(let episodeID):
        ComposeSheet(mode: .publish(episodeID: episodeID))
      case .editPost(let postUID):
        ComposeSheet(mode: .edit(postUID: postUID))
      case .editNarration(let postUID, let source):
        NarrationEditorSheet(postUID: postUID, source: source)
      }
    }
  }

  private var sidebar: some View {
    Sidebar()
      .onGeometryChange(for: CGFloat.self, of: \.size.width) { oldWidth, newWidth in
        guard oldWidth > 0, sidebarWidthRange.contains(newWidth) else { return }
        sidebarWidth = newWidth
      }
      .toolbar(removing: .sidebarToggle)
      .navigationSplitViewColumnWidth(min: sidebarWidthRange.lowerBound, ideal: sidebarWidth, max: sidebarWidthRange.upperBound)
  }

  @ViewBuilder
  private var content: some View {
    switch model.sidebar {
    case .podcasts:
      EpisodeListView()
    case .narrations:
      PostListView(source: .narrations)
    case .posts:
      PostListView(source: .all)
    case .discover:
      DiscoverListView(feed: .discover)
    case .listenLater:
      DiscoverListView(feed: .listenLater)
    }
  }

  private var detail: some View {
    Group {
      if showsListInDetail {
        content
      } else {
        selectedDetail
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      NowPlayingBar()
    }
  }

  @ViewBuilder
  private var selectedDetail: some View {
    switch model.sidebar {
    case .podcasts:
      if let id = model.selectedEpisodeID {
        EpisodeEditorView(episodeID: id)
          .id(id)
      } else {
        Color.clear
          .toolbar { ToolbarSpacer(.flexible) }
      }
    case .narrations, .posts:
      if let uid = model.selectedPostUID {
        NarrateView(postUID: uid)
          .id(uid)
      } else if model.sidebar == .posts {
        EmptyStateView(
          symbol: "mic",
          title: "Narrate a Post",
          message: "Pick a post to read it aloud. Wavelength attaches your narration to the post on Micro.blog."
        )
      } else {
        Color.clear
          .toolbar { ToolbarSpacer(.flexible) }
      }
    case .discover, .listenLater:
      DiscoverDetailView(postID: model.selectedDiscoverID)
    }
  }
}

private struct Sidebar: View {
  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(Library.self) private var library
  @Environment(PostsStore.self) private var posts

  var body: some View {
    List(selection: selection) {
      row(.podcasts, badge: library.episodes.count)
      row(.narrations, badge: posts.narratedPosts.count)
      row(.posts)
      row(.discover)
      row(.listenLater)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      accountSummary
    }
  }

  private var selection: Binding<SidebarItem?> {
    Binding(
      get: { model.sidebar },
      set: { if let item = $0 { model.showSection(item, focusContent: false) } }
    )
  }

  private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
    Label(item.title, systemImage: item.symbol)
      .font(.system(size: 14, weight: .regular))
      .badge(badge)
      .tag(item)
  }

  private var accountSummary: some View {
    SettingsLink {
      HStack(spacing: 8) {
        AvatarView(url: session.profile?.photo, size: 26)
        VStack(alignment: .leading, spacing: 0) {
          Text(session.displayName)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          if let username = session.profile?.username {
            Text("@\(username)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .combine)
      .padding(10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Open Settings")
  }
}
