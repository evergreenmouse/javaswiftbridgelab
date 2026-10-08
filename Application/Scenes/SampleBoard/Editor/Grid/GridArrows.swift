import SwiftUI

struct GridArrows: View {
  /// Fixed SF Symbol size; padding changes with width but arrow size never does.
  private static let arrowSize: CGFloat = 8
  let projection: SampleGridProjection
  let frames: [GridSlot: CGRect]
  let links: [GridLink]

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(links, id: \.self) { link in
        if let arrow = placement(for: link) {
          Image(systemName: "triangle.fill")
            .font(.system(size: Self.arrowSize, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.62))
            .frame(width: Self.arrowSize, height: Self.arrowSize)
            .rotationEffect(arrow.angle + .degrees(90))
            .position(arrow.center)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func frame(for endpoint: LinkEndpoint) -> CGRect? {
    switch endpoint {
    case .position(let index): return frames[projection.slot(forPosition: index)]
    case .decoration:
      guard let decoration = projection.layout.decoration, let slot = frames[decoration.slot]
      else { return nil }
      return slot.insetBy(dx: slot.width * 0.04, dy: slot.height * 0.04)
    }
  }

  /// Position an arrow in the free gap between two shapes, not inside either card.
  private func placement(for link: GridLink) -> ArrowPlacement? {
    guard let source = frame(for: link.from),
      let target = frame(for: link.to)
    else { return nil }
    let delta = CGVector(dx: target.midX - source.midX, dy: target.midY - source.midY)
    let distance = hypot(delta.dx, delta.dy)
    guard distance > 0 else { return nil }
    let direction = CGVector(dx: delta.dx / distance, dy: delta.dy / distance)
    let sourceInset = boundaryDistance(
      source, direction: direction, circular: link.from == .decoration)
    let targetInset = boundaryDistance(
      target, direction: direction, circular: link.to == .decoration)
    let freeDistance = distance - sourceInset - targetInset
    guard freeDistance >= Self.arrowSize else { return nil }
    let middle = sourceInset + freeDistance / 2
    return ArrowPlacement(
      center: CGPoint(
        x: source.midX + direction.dx * middle, y: source.midY + direction.dy * middle),
      angle: .radians(Double(atan2(direction.dy, direction.dx)))
    )
  }

  /// Distance from shape center to its boundary along the connection direction.
  private func boundaryDistance(_ rect: CGRect, direction: CGVector, circular: Bool) -> CGFloat {
    if circular { return rect.width / 2 }
    let x = abs(direction.dx) < 0.0001 ? CGFloat.infinity : rect.width / (2 * abs(direction.dx))
    let y = abs(direction.dy) < 0.0001 ? CGFloat.infinity : rect.height / (2 * abs(direction.dy))
    return min(x, y)
  }
}

private struct ArrowPlacement {
  let center: CGPoint
  let angle: Angle
}
