import SwiftUI

/// Three equal square columns; SwiftUI Grid owns row heights and slot coordinates.
struct GridSizing {
  static let maximumWidth = CardMetrics.maximumSide * 3 + 16 * 2 + 24 * 2
  private static let compactWidth = CardMetrics.compactSide * 3 + 8 * 2 + 12 * 2
  let width: CGFloat
  let columns: Int
  private var spacingScale: CGFloat {
    min(1, max(0, (width - Self.compactWidth) / (Self.maximumWidth - Self.compactWidth)))
  }
  var inset: CGFloat { 8 + 8 * spacingScale }
  var gap: CGFloat { 12 + 12 * spacingScale }
  var side: CGFloat { max(1, (width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)) }
}
