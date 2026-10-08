//
//  NoteComposer.swift
//  JavaSwiftBridgeLab
//
//  Created by Alexandr Opolovnikov on 08.10.26.
//

import SwiftUI

/// A quiet, native composer over the grid; SwiftUI keeps its bottom edge above the keyboard.
struct NoteComposer: View {
  /// Reserve enough scroll space for the folded panel, including its editor and compact footer.
  static let compactHeight: CGFloat = 96
  /// The ViewModel owns the draft, saved text and character limit; this view only owns visual state.
  @Binding var text: String
  let hasChanges: Bool
  let availableWidth: CGFloat
  let availableHeight: CGFloat
  let onSave: () -> Void
  let onCancel: () -> Void
  let onFocusChange: (Bool) -> Void
  @State private var isExpanded = false
  @FocusState private var isFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.orderEditorAppearance) private var appearance

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        if text.isEmpty {
          Text("Add a note…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.leading, 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        TextEditor(text: $text)
          .font(.subheadline)
          .scrollContentBackground(.hidden)
          .focused($isFocused)
          .accessibilityLabel("Note")
          .accessibilityIdentifier("order-note")
      }
      HStack(spacing: 8) {
        Text(String(text.count) + " / " + String(OrderLimits.noteCharacters))
          .font(.caption2.monospacedDigit())
          .accessibilityIdentifier("note-count")
        Spacer(minLength: 4)
        if isFocused || hasChanges {
          Button("Cancel", role: .cancel) {
            onCancel()
            finishEditing()
          }
          .accessibilityIdentifier("note-cancel")
          Button("Save") {
            onSave()
            finishEditing()
          }
          .fontWeight(.medium)
          .disabled(!hasChanges)
          .accessibilityIdentifier("note-save")
        }
        if isFocused {
          Button {
            isFocused = false
          } label: {
            Image(systemName: "keyboard.chevron.compact.down")
              .frame(width: 32, height: 32)
          }
          .accessibilityLabel("Dismiss keyboard")
          .accessibilityIdentifier("note-dismiss-keyboard")
        }
        Button {
          withAnimation(motion) { isExpanded.toggle() }
        } label: {
          // Outward arrows offer expansion; inward arrows offer collapse.
          Image(
            systemName: isExpanded
              ? "arrow.down.right.and.arrow.up.left"
              : "arrow.up.left.and.arrow.down.right"
          )
          .frame(width: 32, height: 32)
        }
        .accessibilityLabel(isExpanded ? "Collapse note" : "Expand note")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("note-expand")
      }
      .font(.caption)
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .frame(minHeight: 32)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(
      width: isExpanded ? availableWidth : min(560, max(1, availableWidth - 16)),
      height: isExpanded
        ? max(Self.compactHeight, availableHeight - 16)
        : min(Self.compactHeight, max(72, availableHeight - 16))
    )
    .background(
      appearance.isRefined
        ? AnyShapeStyle(Color(uiColor: .systemGray5)) : AnyShapeStyle(.thinMaterial),
      in: .rect(cornerRadius: appearance.noteCornerRadius)
    )
    .overlay {
      RoundedRectangle(cornerRadius: appearance.noteCornerRadius)
        .strokeBorder(.secondary.opacity(appearance.isRefined ? 0 : 0.12))
    }
    .onChange(of: isFocused) { _, value in onFocusChange(value) }
    .onDisappear { onFocusChange(false) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("note-composer")
  }

  private var motion: Animation? { reduceMotion ? nil : .snappy(duration: 0.22) }

  /// Save/Cancel finish the editing session while retaining the same native editor instance.
  private func finishEditing() {
    isFocused = false
    withAnimation(motion) { isExpanded = false }
  }
}
