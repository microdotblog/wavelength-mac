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
  @Environment(AppModel.self) private var model
  @State private var columns = NavigationSplitViewVisibility.all

  var body: some View {
    @Bindable var model = model

    NavigationSplitView(columnVisibility: $columns) {
      Sidebar()
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
    } content: {
      content
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
    } detail: {
      detail
        .safeAreaInset(edge: .bottom, spacing: 0) {
          NowPlayingBar()
        }
    }
    .sheet(item: $model.sheet) { sheet in
      switch sheet {
      case .publish(let episodeID):
        ComposeSheet(mode: .publish(episodeID: episodeID))
      case .editPost(let postUID):
        ComposeSheet(mode: .edit(postUID: postUID))
      case .editNarration(let postUID, let source):
        NarrationEditorSheet(postUID: postUID, source: source)
      }
    }
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

  @ViewBuilder
  private var detail: some View {
    switch model.sidebar {
    case .podcasts:
      if let id = model.selectedEpisodeID {
        EpisodeEditorView(episodeID: id)
          .id(id)
      } else {
        EmptyStateView(
          symbol: "waveform",
          title: "No Episode Selected",
          message: "Pick an episode to edit it, or record a new one.",
          actionTitle: "New Episode",
          action: model.startNewEpisode
        )
      }
    case .narrations, .posts:
      if let uid = model.selectedPostUID {
        NarrateView(postUID: uid)
          .id(uid)
      } else {
        EmptyStateView(
          symbol: "mic",
          title: "Narrate a Post",
          message: "Pick a post to read it aloud. Wavelength attaches your narration to the post on Micro.blog."
        )
      }
    case .discover, .listenLater:
      if let id = model.selectedDiscoverID {
        DiscoverDetailView(postID: id)
      } else {
        EmptyStateView(symbol: "sparkles", title: "Pick an Episode", message: "Choose a podcast to see its details. Double-click to play.")
        }
    }
  }
}

private struct Sidebar: View {
  @Environment(AppModel.self) private var model
  @Environment(Session.self) private var session
  @Environment(Library.self) private var library
  @Environment(PostsStore.self) private var posts
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    List(selection: selection) {
      Section("Library") {
        row(.podcasts, badge: library.episodes.count)
        row(.narrations, badge: posts.narratedPosts.count)
      }

      Section("Blog") {
        row(.posts)
      }

      Section("Listen") {
        row(.discover)
        row(.listenLater)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      accountMenu
    }
  }

  private var selection: Binding<SidebarItem?> {
    Binding(get: { model.sidebar }, set: { if let item = $0 { model.sidebar = item } })
  }

  private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
    Label(item.title, systemImage: item.symbol)
      .badge(badge)
      .tag(item)
  }

  private var accountMenu: some View {
    Menu {
      if !session.destinations.isEmpty {
        Picker("Blog", selection: Binding(
          get: { session.selectedDestination?.uid ?? "" },
          set: { uid in
            if let destination = session.destinations.first(where: { $0.uid == uid }) {
              session.select(destination)
              Task { await posts.refresh() }
            }
          }
        )) {
          ForEach(session.destinations) { destination in
            Text(destination.name).tag(destination.uid)
          }
        }
        .pickerStyle(.inline)

        Divider()
      }

      Button("Settings…") { openSettings() }
      Button("Sign Out") { model.signOut() }
    } label: {
      HStack(spacing: 8) {
        AvatarView(url: session.profile?.photo, size: 26)
        VStack(alignment: .leading, spacing: 0) {
          Text(session.displayName)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Text(session.destinationName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .contentShape(.rect)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .padding(10)
  }
}
