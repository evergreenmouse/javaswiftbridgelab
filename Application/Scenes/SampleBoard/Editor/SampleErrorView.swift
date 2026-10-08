import SwiftUI

/// A conditional yellow banner; primary text follows the active light/dark appearance.
struct SampleErrorView: View {
  let message: String

  var body: some View {
    Label {
      Text(message)
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("sample-validation-error")
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color("SampleWarning"))
    }
    .foregroundStyle(.primary)
    .padding(12)
    .background(
      Color("SampleErrorBackground"), in: .rect(cornerRadius: 12)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("sample-error")
  }
}

extension SampleFailure {
  /// Human-readable messages live in Presentation, outside the domain/legacy contracts.
  var message: String {
    switch self {
    case .inactive: "The data source is inactive. Wait for reconnection."
    case .notUpToDate: "The sample data is updating. Try again after loading."
    case .itemMissing: "This sample item no longer exists."
    case .itemLoading: "Wait for the sample item to load."
    case .capacityReached: "A board can contain up to eight samples."
    case .lastItem: "The last sample item cannot be deleted."
    case .conflict: "The samples changed while reordering. Try again."
    case .rejected: "The data source rejected this action. Try again."
    case .invalidSnapshot: "The data source returned invalid sample data."
    case .unsupportedValue(let value): "The data source returned an unsupported value: \(value)."
    }
  }
}
