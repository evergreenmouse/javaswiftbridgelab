import SwiftUI

/// Owns visual state; generic contracts keep source implementation out of the view hierarchy.
struct SampleBoardView<Actions: SampleBoardActions, Data: SampleBoardState>:
  View
{
  let actions: Actions
  let state: Data
  let onClose: @MainActor () -> Void
  let onSave: @MainActor () -> Void
  @State private var interaction = SampleBoardInteractionState()
  @State private var isSavingSample = false
  private var isBusy: Bool {
    !state.canInteract || state.isPerformingCommand || interaction.isBusy
  }
  private var canSave: Bool {
    state.canInteract && canFinishEditing && state.errorMessage == nil
  }
  private var canFinishEditing: Bool {
    !state.isPerformingCommand && !isSavingSample
      && !interaction.isBusy
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if let message = state.errorMessage {
          SampleErrorView(message: message)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        SampleBoardHeader(
          actions: actions, state: state, interaction: interaction, isBusy: isBusy)
        Divider()
        if state.isLoading {
          ProgressView("Loading samples…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("board-loading")
        } else if state.cards.isEmpty {
          ContentUnavailableView(
            "No sample items", systemImage: "square.grid.3x3",
            description: Text(
              state.errorMessage == nil
                ? "This board has no samples yet." : "Check the data source status.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityIdentifier("board-empty")
        } else {
          SampleGridView(
            actions: actions, state: state, interaction: interaction,
            onFinishEditing: finishEditing)
        }
      }
      .foregroundStyle(.primary)
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("Java → Swift Lab")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close", systemImage: "xmark", action: onClose)
            .labelStyle(.iconOnly)
            .disabled(
              state.isPerformingCommand || interaction.reorder != nil
                || interaction.drag.session != nil
            )
            .accessibilityIdentifier("close-sample-board")
        }
        ToolbarItem(placement: .topBarTrailing) {
          if interaction.isEditing {
            Button("Done", action: finishEditing)
              .foregroundStyle(.primary)
              .disabled(!canFinishEditing)
              .accessibilityIdentifier("done-editing")
          } else {
            Button("Save") {
              guard canSave else { return }
              isSavingSample = true
              onSave()
            }
            .foregroundStyle(.primary)
            .disabled(!canSave)
            .accessibilityIdentifier("save-sample")
          }
        }
      }
    }
    .tint(.secondary)
    .task(id: ObjectIdentifier(actions)) { await actions.observe() }
  }

  /// Finishing sample keeps the edited sample on screen, including invalid samples.
  private func finishEditing() {
    guard interaction.isEditing && canFinishEditing else { return }
    withAnimation(.easeOut(duration: 0.18)) { interaction.isEditing = false }
  }
}

/// Layout selection and item count read the scene contracts without owning sample state.
private struct SampleBoardHeader<
  Actions: SampleBoardActions, Data: SampleBoardState
>: View {
  let actions: Actions
  let state: Data
  let interaction: SampleBoardInteractionState
  let isBusy: Bool

  var body: some View {
    HStack {
      Menu {
        ForEach(LayoutCatalog.all) { layout in
          Button {
            guard !isBusy else { return }
            Task {
              await actions.select(layout)
              interaction.isEditing = false
            }
          } label: {
            if layout == state.layout {
              Label(layout.title, systemImage: "checkmark")
            } else {
              Text(layout.title)
            }
          }
          .accessibilityIdentifier("layout-\(layout.id)")
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "square.grid.3x3").foregroundStyle(.secondary)
          Text(state.layout.title).fontWeight(.semibold)
          Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
      }
      .disabled(isBusy)
      .accessibilityLabel("Layout")
      .accessibilityValue(state.layout.title)
      .accessibilityIdentifier("layout-picker")
      Spacer()
      Text("\(state.cards.count) / \(state.layout.capacity)")
        .font(.subheadline.monospacedDigit())
        .accessibilityIdentifier("card-count")
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 24)
  }
}
