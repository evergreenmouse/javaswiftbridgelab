import SwiftUI

/// Owns a typed draft and submits only explicit edits, preserving newer live metric values.
struct CardEditor: View {
  let card: SampleItemSnapshot
  let number: Int
  let onSave: (SampleItemDraft) async -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var draft: SampleItemDraft
  @State private var saveFailed = false
  @State private var isSaving = false

  init(card: SampleItemSnapshot, number: Int, onSave: @escaping (SampleItemDraft) async -> Bool) {
    self.card = card
    self.number = number
    self.onSave = onSave
    _draft = State(initialValue: SampleItemDraft(card: card))
  }

  var body: some View {
    NavigationStack {
      Form {
        if saveFailed {
          Text(
            "Could not save changes. Check the error message on the sample board."
          )
          .foregroundStyle(.primary)
        }
        Section("Sample name") {
          input("Sample name", text: $draft.sampleName, id: "field-1")
        }
        Section("Runtime") {
          Picker("Runtime", selection: $draft.runtime) {
            ForEach(SampleRuntime.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("sample-runtime")
        }
        Section("Iterations") { input("Iterations", text: $draft.iterations, id: "field-3") }
        Section("Metric") { input("Metric", text: $draft.metricValue, id: "field-4") }
        Section("Variant") { input("Variant", text: $draft.variant, id: "field-5") }
      }
      .disabled(isSaving)
      .foregroundStyle(.primary)
      .navigationTitle("Card \(number)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isSaving)
            .accessibilityIdentifier("cancel-editor")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard !isSaving else { return }
            isSaving = true
            Task {
              let saved = await onSave(draft)
              isSaving = false
              if saved { dismiss() } else { saveFailed = true }
            }
          }
          .disabled(isSaving)
          .accessibilityIdentifier("save-editor")
        }
      }
    }
    .tint(.secondary)
    .presentationDetents([.large])
    .interactiveDismissDisabled(isSaving || draft != SampleItemDraft(card: card))
  }

  /// Stable identifiers preserve existing UI automation while named bindings prevent index mistakes.
  private func input(_ title: String, text: Binding<String>, id: String) -> some View {
    TextField(title, text: text, prompt: Text(title).foregroundStyle(.primary), axis: .vertical)
      .lineLimit(1...6)
      .autocorrectionDisabled()
      .accessibilityLabel(title)
      .accessibilityIdentifier(id)
  }
}
