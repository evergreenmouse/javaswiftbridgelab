import SwiftUI

struct CardMetrics {
  // Fits a sign, ten monospaced caption digits and grouping separators at the default text size.
  static let compactSide: CGFloat = 109
  static let maximumSide: CGFloat = 136
  static let cornerRadius: CGFloat = 8
  let side: CGFloat
  let headerHeight: CGFloat = 6
  /// Recover content width on narrow phones without changing the text style.
  var padding: CGFloat { min(8, max(6, 6 + (side - Self.compactSide) / 4)) }
}

extension SampleRuntime {
  var color: Color { self == .java ? Color("JavaAccent") : Color("SwiftAccent") }
}

struct CardFace: View {
  let card: SampleItemSnapshot
  let number: Int
  let metrics: CardMetrics

  var body: some View {
    VStack(spacing: 0) {
      card.runtime.color
        .frame(height: metrics.headerHeight)
        .accessibilityHidden(true)
      if card.isLoading {
        ProgressView("Loading…")
          .font(.caption)
          .foregroundStyle(.primary)
          .tint(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityIdentifier("card-loading-\(number)")
      } else {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 1) {
            field(card.sampleName, weight: .semibold)
            field(card.runtime.rawValue, color: card.runtime.color, weight: .semibold)
          }
          Spacer(minLength: 0)
          VStack(alignment: .leading, spacing: 1) {
            field(card.iterations, weight: .medium, minimumScaleFactor: 1)
            field(
              card.metricValue.isEmpty ? "—" : "\(card.metricValue)", color: card.runtime.color,
              weight: .medium)
          }
          Spacer(minLength: 0)
          field(card.variant, font: .caption2)
        }
        .padding(metrics.padding)
      }
    }
    .frame(width: metrics.side, height: metrics.side)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
        .strokeBorder(
          card.runtime.color,
          lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
    .contentShape(.rect(cornerRadius: CardMetrics.cornerRadius))
  }

  /// Compact display may truncate labels; iterations keeps the requested font size.
  private func field(
    _ value: String, font: Font = .caption, color: Color = .primary, weight: Font.Weight = .regular,
    minimumScaleFactor: CGFloat = 0.75
  ) -> some View {
    Text(value.isEmpty ? "—" : value)
      .font(font.weight(weight))
      .monospacedDigit()
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(minimumScaleFactor)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AddCardFace: View {
  var body: some View {
    RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
      .fill(Color.secondary.opacity(0.035))
      .overlay {
        RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
          .strokeBorder(
            Color.secondary.opacity(0.65),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }
      .overlay {
        Image(systemName: "plus")
          .font(.body.weight(.medium))
          .foregroundStyle(Color.secondary)
      }
      .contentShape(.rect(cornerRadius: CardMetrics.cornerRadius))
  }
}

/// Two faces share the same slot; the front is the add tile, the back is the copy.
struct CardFlip: View {
  let card: SampleItemSnapshot
  let number: Int
  let metrics: CardMetrics
  let reduceMotion: Bool
  /// Animate one reveal for this card identity; no sample data is changed by the effect.
  @State private var revealed = false

  var body: some View {
    ZStack {
      AddCardFace()
        .opacity(reduceMotion ? (revealed ? 0 : 1) : 1)
        .modifier(FlipFace(angle: reduceMotion ? 0 : (revealed ? 180 : 0)))
      CardFace(card: card, number: number, metrics: metrics)
        .opacity(reduceMotion ? (revealed ? 1 : 0) : 1)
        .modifier(FlipFace(angle: reduceMotion ? 0 : (revealed ? 0 : -180)))
    }
    .task {
      withAnimation(.easeInOut(duration: reduceMotion ? 0.16 : 0.48)) { revealed = true }
    }
    .allowsHitTesting(false)
  }
}

/// Hide back-facing content continuously during interpolation, not at the state boundary.
private struct FlipFace: AnimatableModifier {
  nonisolated var animatableData: Double

  init(angle: Double) { animatableData = angle }

  func body(content: Content) -> some View {
    content
      .opacity(abs(animatableData) < 90 ? 1 : 0)
      .rotation3DEffect(.degrees(animatableData), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
  }
}

/// Matches the delete icon's size; placement and edit-mode movement belong to the grid.
struct CardWarningBadge: View {
  var body: some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .symbolRenderingMode(.palette)
      .font(.system(size: 24))
      .foregroundStyle(Color.black, Color("SampleWarning"))
      .frame(width: 44, height: 44)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

struct DeleteCardButton: View {
  let number: Int
  let action: () -> Void

  var body: some View {
    Button(role: .destructive, action: action) {
      Image(systemName: "xmark.circle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.primary, Color(uiColor: .systemBackground))
        .font(.system(size: 24))
        .frame(width: 44, height: 44)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Delete card \(number)")
    .accessibilityIdentifier("delete-\(number)")
  }
}
