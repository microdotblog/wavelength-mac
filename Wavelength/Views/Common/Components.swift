import SwiftUI

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let message: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: symbol)
    } description: {
      Text(message)
    } actions: {
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct AvatarView: View {
  let url: URL?
  var size: CGFloat = 32

  var body: some View {
    AsyncImage(url: url) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable()
          .foregroundStyle(.tertiary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(.circle)
  }
}

struct ArtworkView: View {
  let url: URL?
  var size: CGFloat = 44
  var cornerRadius: CGFloat = 8

  var body: some View {
    AsyncImage(url: url) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else {
        ZStack {
          Color.paperAlt
          Image(systemName: "waveform")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: cornerRadius))
  }
}

struct KindBadge: View {
  let kind: PostKind

  var body: some View {
    Label(kind.label, systemImage: kind.symbol)
      .font(.caption.weight(.semibold))
      .labelStyle(.titleAndIcon)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .foregroundStyle(Color.accentColor)
      .background(Color.accentColor.opacity(0.12), in: .capsule)
  }
}

struct ToastOverlay: View {
  @Environment(Toasts.self) private var toasts

  var body: some View {
    VStack {
      Spacer()

      if let toast = toasts.current {
        Text(toast.message)
          .font(.callout.weight(.medium))
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .glassEffect(.regular, in: .capsule)
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .id(toast.id)
      }
    }
    .animation(.spring(duration: 0.35), value: toasts.current)
    .allowsHitTesting(false)
  }
}

struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal: proposal, subviews: subviews)
    let height = rows.last.map { $0.y + $0.height } ?? 0
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
      var x = bounds.minX

      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
    }
  }

  private struct Row {
    var indices: [Int] = []
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
    let maxWidth = proposal.width ?? .infinity
    var rows: [Row] = [Row()]

    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      var row = rows[rows.count - 1]
      let proposedWidth = row.indices.isEmpty ? size.width : row.width + spacing + size.width

      if proposedWidth > maxWidth, !row.indices.isEmpty {
        let y = row.y + row.height + spacing
        rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
        continue
      }

      row.indices.append(index)
      row.width = proposedWidth
      row.height = max(row.height, size.height)
      rows[rows.count - 1] = row
    }

    return rows
  }
}

struct ChipToggle: View {
  let title: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if isOn {
          Image(systemName: "checkmark")
            .font(.caption2.weight(.bold))
        }
        Text(title)
      }
      .font(.callout)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .foregroundStyle(isOn ? Color.white : Color.primary)
      .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12), in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}
