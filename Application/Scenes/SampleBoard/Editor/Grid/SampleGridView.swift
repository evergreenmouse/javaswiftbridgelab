import SwiftUI
import UIKit

/// Native Grid measures slots; stable UIKit card hosts own drag gestures and landing.
struct SampleGridView<Actions: SampleBoardActions, Data: SampleBoardState>: View {
  let actions: Actions
  let state: Data
  let interaction: SampleBoardInteractionState
  let onFinishEditing: () -> Void
  @State private var editingCard: SampleItemSnapshot?
  /// Global frames translate UIKit pointer positions into local SwiftUI slots.
  @State private var canvasFrame: CGRect = .zero
  @State private var slotFrames: [GridSlot: CGRect] = [:]
  @State private var leadingCardFrame: CGRect = .zero
  @State private var viewportFrame: CGRect = .zero
  @State private var fingerPoint: CGPoint = .zero
  @State private var addFeedback = 0
  @State private var scrollPosition = ScrollPosition(y: 0)
  @State private var scrollMetrics = ScrollMetrics()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  private var displayedCards: [SampleItemSnapshot] {
    interaction.reorder?.cards(from: state.cards) ?? state.cards
  }
  private var liftedCardID: UUID? { interaction.drag.session?.cardID }
  private var originalDragIndex: Int? { interaction.drag.session?.originalIndex }
  private var isDragEnding: Bool { interaction.drag.isLanding }
  private var isBusy: Bool {
    !state.canInteract || state.isPerformingCommand || interaction.isBusy
  }
  private var motion: Animation {
    reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 0.86)
  }

  var body: some View {
    GeometryReader { viewport in
      let width = min(
        GridSizing.maximumWidth, max(1, viewport.size.width - 8))
      let sizing = GridSizing(width: width, columns: state.layout.columns)
      ScrollView {
        VStack(spacing: 18) {
          grid(sizing: sizing)
            .onGeometryChange(for: CGRect.self) {
              $0.frame(in: .global)
            } action: { newFrame in
              // Global frame conversion may introduce subpixel size noise during scrolling.
              let resized = canvasFrame.size != .zero && (
                abs(canvasFrame.width - newFrame.width) > 1
                  || abs(canvasFrame.height - newFrame.height) > 1)
              canvasFrame = newFrame
              if interaction.reorder != nil {
                if resized {
                  cancelPreview()
                } else if !isDragEnding {
                  _ = previewReorder()
                }
              }
            }
          Text(
            interaction.isEditing
              ? "Drag to reorder · tap × to delete"
              : "Tap to edit · hold to move or delete"
          )
          .font(.footnote)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
          .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, state.layout.separatesFirstCard ? 18 : 12)
        .frame(
          minHeight: max(0, viewport.size.height - 12),
          alignment: .top
        )
        .background {
          // Only unoccupied canvas receives this tap; card controls keep their own actions.
          Color.clear
            .contentShape(.rect)
            .onTapGesture(perform: onFinishEditing)
            .accessibilityHidden(true)
        }
      }
      .safeAreaPadding(.bottom, 12)
      .scrollPosition($scrollPosition)
      .scrollDisabled(state.isPerformingCommand || liftedCardID != nil)
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        viewportFrame = $0
      }
      .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
        ScrollMetrics(
          offset: geometry.contentOffset.y + geometry.contentInsets.top,
          maximum: max(
            0,
            geometry.contentSize.height - geometry.containerSize.height
              + geometry.contentInsets.top + geometry.contentInsets.bottom)
        )
      } action: { _, value in
        scrollMetrics = value
      }
      .task(id: liftedCardID) {
        guard interaction.reorder != nil else { return }
        while !Task.isCancelled && interaction.reorder != nil && !isDragEnding {
          do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
          autoScroll()
        }
      }
    }

    .sheet(item: $editingCard) { card in
      CardEditor(card: card, number: state.number(id: card.id) ?? 1) { draft in
        await actions.update(original: card, draft: draft)
      }
    }
    .task(id: interaction.flippingID) {
      guard let current = interaction.flippingID else { return }
      do { try await Task.sleep(for: .milliseconds(reduceMotion ? 190 : 520)) } catch { return }
      guard interaction.flippingID == current else { return }
      withAnimation(motion) { interaction.flippingID = nil }
    }
    .sensoryFeedback(.impact(weight: .light), trigger: addFeedback)
    .onChange(of: state.layout.id) { _, _ in
      cancelPreview()
      scrollPosition.scrollTo(y: 0)
    }
    .onChange(of: state.cards.map(\.id)) { _, arrangement in
      if let preview = interaction.reorder, arrangement != preview.payload.arrangement {
        cancelPreview()
      }
    }
    .onChange(of: state.canInteract) { _, available in
      if !available { cancelPreview() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        cancelPreview()
        interaction.flippingID = nil
      }
    }
    .onDisappear {
      cancelPreview()
      interaction.flippingID = nil
    }
  }

  /// Grid lays out fixed square cells; empty cells preserve the agreed three-column schemes.
  private func grid(sizing: GridSizing) -> some View {
    let projection = state.projection
    let coordinateSpace = interaction.editorID
    return VStack(spacing: 18) {
      if state.layout.separatesFirstCard {
        Color.clear
          .frame(width: sizing.side, height: sizing.side)
          .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(coordinateSpace))
          } action: { leadingCardFrame = $0 }
          .frame(maxWidth: .infinity)
          .padding(sizing.inset)
          .background {
            RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.045))
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      Grid(horizontalSpacing: sizing.gap, verticalSpacing: sizing.gap) {
        ForEach(projection.visibleRows, id: \.self) { row in
          GridRow {
            ForEach(0..<state.layout.columns, id: \.self) { column in
              let slot = GridSlot(row, column)
              cell(at: slot, sizing: sizing)
                .frame(width: sizing.side, height: sizing.side)
                .onGeometryChange(for: CGRect.self) {
                  $0.frame(in: .named(coordinateSpace))
                } action: { slotFrames[slot] = $0 }
            }
          }
        }
      }
      .padding(sizing.inset)
    }
    .frame(width: sizing.width)
    .coordinateSpace(name: interaction.editorID)
    .overlay {
      GridArrows(
        projection: projection, frames: slotFrames,
        links: projection.visibleLinks(showAdd: interaction.flippingID == nil))
    }
    .overlay(alignment: .topLeading) {
      ZStack(alignment: .topLeading) {
        if let liftedCardID, let index = displayedCards.firstIndex(where: { $0.id == liftedCardID }),
          let frame = frame(forCardIndex: index)
        {
          RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
            .fill(Color.secondary.opacity(0.07))
            .overlay {
              RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                .strokeBorder(
                  Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // A single ForEach keeps UIKit hosts alive when cards cross GridRow boundaries.
        ForEach(displayedCards) { card in
          let index = displayedCards.firstIndex(where: { $0.id == card.id }) ?? 0
          let frame = frame(forCardIndex: index) ?? .zero
          movableCard(card, side: sizing.side)
            .position(x: frame.midX, y: frame.midY)
            .opacity(frame.isEmpty ? 0 : 1)
            .accessibilityHidden(frame.isEmpty)
            .transaction { if liftedCardID == card.id { $0.animation = nil } }
            .transition(.opacity)
        }
      }
    }
    .animation(motion, value: displayedCards.map(\.id))
    .animation(motion, value: state.layout.id)
  }

  @ViewBuilder
  private func cell(at slot: GridSlot, sizing: GridSizing) -> some View {
    let projection = state.projection
    if let position = projection.addPosition,
      projection.slot(forPosition: position) == slot, interaction.flippingID == nil
    {
      Button(action: addCard) { AddCardFace() }
        .buttonStyle(.plain)
        .disabled(isBusy || !state.canAdd)
        .accessibilityLabel("Add a copy of the previous card")
        .accessibilityIdentifier("add-card")
        .transition(.opacity)
    } else if let decoration = state.layout.decoration, decoration.slot == slot {
      Circle()
        .fill(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay {
          Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.5)
        }
        .overlay {
          Text(decoration.label)
            .font(.title2.weight(.medium))
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.6)
        }
        .padding(sizing.side * 0.04)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    } else {
      Color.clear.allowsHitTesting(false).accessibilityHidden(true)
    }
  }

  private func frame(forCardIndex index: Int) -> CGRect? {
    if state.layout.separatesFirstCard && index == 0 { return leadingCardFrame }
    return slotFrames[state.projection.slot(forPosition: index - state.layout.leadingCount)]
  }

  /// The flat card layer preserves native drag sessions across rows and the separate trigger slot.
  private func movableCard(_ card: SampleItemSnapshot, side: CGFloat) -> some View {
    let number = displayedCards.firstIndex(where: { $0.id == card.id }).map { $0 + 1 } ?? 1
    let showsDeleteButton =
      interaction.isEditing && state.canDelete(id: card.id) && interaction.flippingID == nil
      && liftedCardID == nil
    return ZStack {
      if interaction.flippingID == card.id {
        CardFlip(
          card: card, number: number, metrics: CardMetrics(side: side),
          reduceMotion: reduceMotion)
      } else {
        SystemCardDrag(
          cardID: card.id,
          editorID: interaction.editorID,
          isEnabled: !isBusy && !card.isLoading,
          onLongPress: { withAnimation(motion) { interaction.isEditing = true } },
          onBegin: { beginReorder(card, at: $0) },
          onMove: { point in
            guard interaction.reorder != nil, !isDragEnding else { return false }
            fingerPoint = point
            return previewReorder()
          },
          onAcceptDrop: { point in
            fingerPoint = point
            return previewReorder()
          },
          onWillEnd: { committed in
            interaction.beginLanding()
            if !committed { cancelPreview() }
          },
          onEnd: { committed in
            guard let sessionID = interaction.drag.session?.id else { return }
            Task {
              if committed, let preview = interaction.reorder,
                preview.payload.cardID == card.id
              {
                await actions.reorder(
                  ids: preview.arrangement, expectedArrangement: preview.payload.arrangement)
              }
              // Reveal once UIKit has landed its preview, without a SwiftUI crossfade.
              var transaction = Transaction(animation: nil)
              transaction.disablesAnimations = true
              withTransaction(transaction) {
                if interaction.drag.session?.id == sessionID {
                  interaction.reorder = nil
                  interaction.endDrag(sessionID: sessionID)
                }
              }
            }
          },
          previewFrame: { committed in
            let index =
              committed
              ? liftedCardID.flatMap { id in displayedCards.firstIndex { $0.id == id } }
              : liftedCardID.flatMap { state.cardIndex(id: $0) } ?? originalDragIndex
            return index.flatMap {
              frame(forCardIndex: $0)?.offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY)
            }
          }
        ) {
          Button {
            if !isBusy && !card.isLoading { editingCard = card }
          } label: {
            CardFace(card: card, number: number, metrics: CardMetrics(side: side))
              .opacity(liftedCardID == card.id ? 0 : 1)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .frame(width: side, height: side)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Card \(number)")
    .accessibilityValue(card.isLoading ? "Loading…" : accessibilityFields(card))
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("card-\(number)")
    .accessibilityAction { if !isBusy && !card.isLoading { editingCard = card } }
    .accessibilityActions {
      if !isBusy {
        if !card.isLoading {
          Button("Move backward") { accessibleMove(card, by: -1) }
          Button("Move forward") { accessibleMove(card, by: 1) }
        }
        if state.canDelete(id: card.id) {
          Button("Delete") { deleteCard(card) }
        }
      }
    }
    .overlay(alignment: .topTrailing) {
      if card.hasError {
        CardWarningBadge()
          .offset(x: showsDeleteButton ? -22 : 22, y: -22)
          .opacity(liftedCardID == card.id ? 0 : 1)
          .animation(motion, value: showsDeleteButton)
      }
    }
    .overlay(alignment: .topTrailing) {
      if showsDeleteButton {
        DeleteCardButton(number: number) { deleteCard(card) }
          .offset(x: 22, y: -22)
          .transition(.scale.combined(with: .opacity))
      }
    }
  }

  /// UIKit reports global positions; hit testing uses the local grid canvas.
  private var dropPoint: CGPoint {
    CGPoint(x: fingerPoint.x - canvasFrame.minX, y: fingerPoint.y - canvasFrame.minY)
  }

  /// Store identities only; source fields remain live during the UIKit gesture.
  private func beginReorder(_ card: SampleItemSnapshot, at point: CGPoint) -> Bool {
    guard !isBusy, !card.isLoading, let index = state.cardIndex(id: card.id) else { return false }
    let payload = SampleCardTransfer(
      editorID: interaction.editorID, cardID: card.id, arrangement: state.cards.map(\.id))
    interaction.reorder = SampleCardReorderPreview(payload: payload)
    interaction.beginDrag(cardID: card.id, index: index)
    fingerPoint = point
    return true
  }

  /// Accept occupied measured slots inside the visible viewport, including the source slot.
  private func previewReorder() -> Bool {
    guard let preview = interaction.reorder, !isDragEnding,
      state.canInteract, !state.isPerformingCommand,
      preview.payload.arrangement == state.cards.map(\.id),
      viewportFrame.contains(fingerPoint),
      let destination = displayedCards.indices.first(where: {
        frame(forCardIndex: $0)?.contains(dropPoint) == true
      })
    else { return false }
    withAnimation(motion) { interaction.reorder?.move(to: destination) }
    return true
  }

  /// Restore current source positions; UIKit may still be returning its lifted preview.
  private func cancelPreview() {
    guard interaction.reorder != nil else { return }
    withAnimation(motion) { interaction.reorder = nil }
  }

  /// Start the reveal animation only after the source has created an item identity.
  private func addCard() {
    guard !isBusy else { return }
    Task {
      guard let id = await actions.appendCopy() else { return }
      interaction.flippingID = id
      addFeedback += 1
    }
  }

  /// ViewModel reports command failures through the screen banner.
  private func deleteCard(_ card: SampleItemSnapshot) {
    guard !isBusy else { return }
    Task { await actions.delete(id: card.id) }
  }

  /// VoiceOver uses the same application action as pointer reordering.
  private func accessibleMove(_ card: SampleItemSnapshot, by offset: Int) {
    guard !isBusy else { return }
    Task { await actions.move(id: card.id, by: offset) }
  }

  /// VoiceOver receives full values, including strings visually truncated in a compact card.
  private func accessibilityFields(_ card: SampleItemSnapshot) -> String {
    let fields =
      "Sample name: \(card.sampleName), Runtime: \(card.runtime.rawValue), Iterations: \(card.iterations), Metric: \(card.metricValue), Variant: \(card.variant)"
    return card.hasError ? "\(fields), Validation error" : fields
  }

  /// Move smoothly near viewport edges; clamp to the measured scrollable range.
  private func autoScroll() {
    guard viewportFrame.width > 0,
      (viewportFrame.minX...viewportFrame.maxX).contains(fingerPoint.x)
    else { return }
    let edge: CGFloat = 60
    let topDistance = fingerPoint.y - viewportFrame.minY
    let bottomDistance = viewportFrame.maxY - fingerPoint.y
    let velocity: CGFloat
    if topDistance < edge {
      velocity = -min(1, max(0, (edge - topDistance) / edge)) * 7
    } else if bottomDistance < edge {
      velocity = min(1, max(0, (edge - bottomDistance) / edge)) * 7
    } else {
      return
    }
    let target = min(scrollMetrics.maximum, max(0, scrollMetrics.offset + velocity))
    guard abs(target - scrollMetrics.offset) > 0.25 else { return }
    scrollPosition.scrollTo(y: target)
  }

}

/// Scroll bounds are sampled from SwiftUI; no keyboard/frame notification observers are needed.
private struct ScrollMetrics: Equatable {
  var offset: CGFloat = 0
  var maximum: CGFloat = 0
}
