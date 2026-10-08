import Foundation
import LegacySampleMock
import Testing

@testable import JavaSwiftBridgeLab

@MainActor
private final class ModelListenerRecorder: NSObject, CompositeSampleModelListener {
  var changeCount = 0
  var onChange: (() -> Void)?
  var onStateChange: (() -> Void)?

  nonisolated func onCompositeSampleModelChange() {
    MainActor.assumeIsolated { changeCount += 1; onChange?() }
  }
  nonisolated func onCompositeSampleModelStateChange() {
    MainActor.assumeIsolated { onStateChange?() }
  }
  nonisolated func onCompositeSampleModelUpToDate() {}
  nonisolated func onCompositeSampleModelInactive() {}
  nonisolated func onCompositeSampleModelNotUpToDate() {}
  nonisolated func onCompositeSampleModelLayoutTagChange() {}
}

@MainActor
struct CompositeSampleModelListenerTests {
  @Test func listenerArrayRetainsObjectsAndUsesIdentityForRegistration() throws {
    let model = CompositeSampleModel(loadDelay: 0, itemDelay: 0, metricInterval: 0)
    var listener: ModelListenerRecorder? = ModelListenerRecorder()
    weak let retainedListener = listener
    model.addListener(try #require(listener))
    model.addListener(try #require(listener))
    #expect(model.listenerCount == 1 && model.isActive)
    listener = nil
    #expect(retainedListener != nil)
    model.removeListener(ModelListenerRecorder())
    #expect(model.listenerCount == 1 && model.isActive)
    model.removeListener(try #require(retainedListener))
    #expect(model.listenerCount == 0 && !model.isActive && !model.isUpToDate)
    model.removeListener(ModelListenerRecorder())
    #expect(model.listenerCount == 0)
  }

  @Test func listenerCanRemoveItselfDuringNotification() {
    let model = CompositeSampleModel(loadDelay: 0, itemDelay: 0, metricInterval: 0)
    let first = ModelListenerRecorder()
    let second = ModelListenerRecorder()
    model.addListener(first)
    model.addListener(second)
    model.simulateUp(toDate: true)
    defer { model.removeListener(first); model.removeListener(second) }
    first.onChange = { [weak first, weak model] in
      if let first { model?.removeListener(first) }
    }
    model.simulateLegacyTick()
    #expect(first.changeCount == 1 && second.changeCount == 1)
    #expect(model.listenerCount == 1 && model.isActive)
    model.simulateLegacyTick()
    #expect(first.changeCount == 1 && second.changeCount == 2)
  }

  @Test func removingLastListenerInsideRegistrationDoesNotLeaveMockWorkRunning() async throws {
    let model = CompositeSampleModel(loadDelay: 0.02, itemDelay: 0, metricInterval: 0.01)
    let listener = ModelListenerRecorder()
    listener.onStateChange = { [weak listener, weak model] in
      if let listener { model?.removeListener(listener) }
    }
    model.addListener(listener)
    #expect(model.listenerCount == 0 && !model.isActive && !model.isUpToDate)
    try await Task.sleep(for: .milliseconds(60))
    #expect(model.items.isEmpty)
    #expect(model.value(forKey: "metricTimer") == nil)
  }
}
