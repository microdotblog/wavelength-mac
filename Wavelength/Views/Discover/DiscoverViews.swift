import SwiftUI

struct DiscoverListView: View {
  let feed: DiscoverStore.Feed

  @Environment(AppModel.self) private var model
  @Environment(DiscoverStore.self) private var discover
  @Environment(NowPlaying.self) private var nowPlaying
  @Environment(Session.self) private var session
  @Environment(Toasts.self) private var toasts
  @Environment(\.openURL) private var openURL

  var body: some View {
    @Bindable var model = model
    let state = discover.state(feed)
    let posts = discover.visiblePosts(feed)

    Group {
      if posts.isEmpty {
        if state.isLoading || !state.didHydrate {
          ProgressView()
        } else if let message = state.errorMessage {
          EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn’t Load \(feed.title)", message: message, actionTitle: "Try Again") {
            Task { await discover.refresh(feed) }
          }
        } else {
          EmptyStateView(symbol: feed == .discover ? "sparkles" : "bookmark", title: feed.emptyTitle, message: feed.emptyBody)
        }
      } else {
        List(selection: $model.selectedDiscoverID) {
          ForEach(posts) { post in
            DiscoverRow(post: post)
              .tag(post.id)
              .contextMenu { menu(for: post) }
              .onAppear {
                if post.id == posts.last?.id {
                  Task { await discover.loadMore(feed) }
                }
              }
          }

          if state.isLoadingMore {
            HStack {
              Spacer()
              ProgressView().controlSize(.small)
              Spacer()
            }
          }
        }
        .contextMenu(forSelectionType: String.self) { _ in
        } primaryAction: { ids in
          if let id = ids.first, let post = discover.post(id) {
            nowPlaying.toggle(post)
          }
        }
      }
    }
    .navigationTitle(feed.title)
    .toolbar {
      ToolbarItem {
        Button {
          Task { await discover.refresh(feed) }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(state.isLoading)
      }
    }
    .task(id: feed) {
      if !discover.state(feed).didHydrate {
        await discover.refresh(feed)
      }
    }
  }

  @ViewBuilder
  private func menu(for post: DiscoverPost) -> some View {
    Button(nowPlaying.isCurrent(post) && nowPlaying.isPlaying ? "Pause" : "Play", systemImage: "play.fill") {
      nowPlaying.toggle(post)
    }

    if let url = URL(string: post.url) {
      Button("Open Post", systemImage: "safari") { openURL(url) }
    }

    if session.isSignedIn {
      Divider()
      ListenLaterButton(post: post)
    }
  }
}

struct ListenLaterButton: View {
  let post: DiscoverPost

  @Environment(DiscoverStore.self) private var discover
  @Environment(Toasts.self) private var toasts

  var body: some View {
    if post.isSaved {
      Button("Remove from Listen Later", systemImage: "bookmark.slash") {
        Task {
          do {
            try await discover.removeFromLater(post)
            toasts.show("Removed from Listen Later.")
          } catch {
            toasts.show(error.localizedDescription)
          }
        }
      }
    } else {
      Button("Listen Later", systemImage: "bookmark") {
        Task {
          do {
            try await discover.saveForLater(post)
            toasts.show("Saved to Listen Later.")
          } catch {
            toasts.show(error.localizedDescription)
          }
        }
      }
    }
  }
}

struct DiscoverRow: View {
  let post: DiscoverPost

  @Environment(NowPlaying.self) private var nowPlaying

  private var isCurrent: Bool { nowPlaying.isCurrent(post) }

  var body: some View {
    HStack(spacing: 12) {
      ArtworkView(url: post.artworkURL, size: 48)

      VStack(alignment: .leading, spacing: 3) {
        Text(post.displayTitle)
          .font(.body.weight(.semibold))
          .lineLimit(2)

        if !post.title.trimmed.isEmpty {
          Text(post.sourceLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Text([post.timestamp, post.durationLabel].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      if post.isSaved {
        Image(systemName: "bookmark.fill")
          .foregroundStyle(.tertiary)
          .help("In Listen Later")
      }

      Button {
        nowPlaying.toggle(post)
      } label: {
        PlayPauseCircle(isPlaying: isCurrent && nowPlaying.isPlaying, size: 26)
      }
      .buttonStyle(.plain)
      .help(isCurrent && nowPlaying.isPlaying ? "Pause" : "Play")
    }
    .padding(.vertical, 4)
  }
}

struct DiscoverDetailView: View {
  let postID: String

  @Environment(DiscoverStore.self) private var discover
  @Environment(NowPlaying.self) private var nowPlaying
  @Environment(Session.self) private var session
  @Environment(\.openURL) private var openURL

  var body: some View {
    if let post = discover.post(postID) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .top, spacing: 20) {
            ArtworkView(url: post.artworkURL, size: 160, cornerRadius: 16)
              .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
              Text(post.displayTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

              Button {
                if let url = post.authorURL { openURL(url) }
              } label: {
                HStack(spacing: 8) {
                  AvatarView(url: post.authorAvatar, size: 24)
                  Text(post.sourceLabel)
                    .font(.headline)
                  if !post.authorUsername.isEmpty {
                    Text("@\(post.authorUsername)")
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .buttonStyle(.plain)
              .disabled(post.authorURL == nil)

              Text([post.timestamp, post.durationLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                .foregroundStyle(.secondary)

              HStack(spacing: 10) {
                Button {
                  nowPlaying.toggle(post)
                } label: {
                  Label(
                    nowPlaying.isCurrent(post) && nowPlaying.isPlaying ? "Pause" : "Play",
                    systemImage: nowPlaying.isCurrent(post) && nowPlaying.isPlaying ? "pause.fill" : "play.fill"
                  )
                  .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if session.isSignedIn {
                  ListenLaterButton(post: post)
                    .controlSize(.large)
                }

                if let url = URL(string: post.url) {
                  Button("Open Post", systemImage: "safari") { openURL(url) }
                    .controlSize(.large)
                }
              }
              .padding(.top, 6)
            }
          }

          if !post.displaySummary.isEmpty {
            Text(post.displaySummary)
              .font(.body)
              .foregroundStyle(.primary)
              .textSelection(.enabled)
              .frame(maxWidth: 640, alignment: .leading)
          }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .navigationTitle(post.sourceLabel)
    } else {
      EmptyStateView(symbol: "sparkles", title: "Pick an Episode", message: "Choose a podcast to see its details.")
    }
  }
}

struct NowPlayingBar: View {
  @Environment(NowPlaying.self) private var nowPlaying
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var nowPlaying = nowPlaying

    if let post = nowPlaying.post {
      HStack(spacing: 14) {
        Button {
          if model.sidebar.feed == nil {
            model.sidebar = .discover
          }

          model.selectedDiscoverID = post.id
        } label: {
          HStack(spacing: 10) {
            ArtworkView(url: post.artworkURL, size: 38, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
              Text(post.displayTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
              Text(post.sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: 260, alignment: .leading)
        }
        .buttonStyle(.plain)

        Button { nowPlaying.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
          .buttonStyle(.borderless)
          .help("Back 15 seconds")

        Button { nowPlaying.toggle() } label: {
          PlayPauseIcon(isPlaying: nowPlaying.isPlaying, size: 17)
            .frame(width: 28, height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(nowPlaying.isPlaying ? "Pause" : "Play")

        Button { nowPlaying.skip(by: 30) } label: { Image(systemName: "goforward.30") }
          .buttonStyle(.borderless)
          .help("Forward 30 seconds")

        Text(Formatting.duration(nowPlaying.currentTime))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)

        ScrubBar(progress: nowPlaying.progress) { nowPlaying.seek(fraction: $0) }
          .frame(height: 20)
          .overlay {
            if nowPlaying.isBuffering {
              ProgressView().controlSize(.mini)
            }
          }

        Text(Formatting.duration(nowPlaying.duration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)

        Menu {
          Picker("Speed", selection: $nowPlaying.rate) {
            ForEach(NowPlaying.rates, id: \.self) { rate in
              Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "×").tag(rate)
            }
          }
          .pickerStyle(.inline)
        } label: {
          Text(nowPlaying.rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
            .font(.caption.monospacedDigit().weight(.semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Playback speed")

        Button { nowPlaying.stop() } label: { Image(systemName: "xmark") }
          .buttonStyle(.borderless)
          .help("Stop")
      }
      .font(.title3)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
      .padding(12)
    }
  }
}
