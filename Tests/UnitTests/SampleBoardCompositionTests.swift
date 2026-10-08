import LegacySampleMock
import SwiftUI
import Testing
import UIKit

@testable import JavaSwiftBridgeLab

@MainActor
struct SampleBoardCompositionTests {
  private final class Delegate: SampleBoardViewControllerDelegate {
    var closingController: SampleBoardViewController?
    var savingSampleController: SampleBoardViewController?
    func sampleBoardDidRequestClose(_ controller: SampleBoardViewController) {
      closingController = controller
    }
    func sampleBoardDidRequestSave(_ controller: SampleBoardViewController) {
      savingSampleController = controller
    }
  }

  private final class Builder: SampleBoardBuilding {
    var models: [CompositeSampleModel] = []
    weak var receivedDelegate: (any SampleBoardViewControllerDelegate)?
    func makeViewController(
      model: CompositeSampleModel, delegate: any SampleBoardViewControllerDelegate
    ) -> SampleBoardViewController {
      models.append(model)
      receivedDelegate = delegate
      return SampleBoardViewController(
        viewModel: SampleBoardViewModel(agent: TestSampleAgent()), delegate: delegate)
    }
  }

  @Test func legacyCoordinatorReusesModelAndCreatesFreshEditorControllers() throws {
    let model = CompositeSampleModel(loadDelay: 0, itemDelay: 0, metricInterval: 0)
    let builder = Builder()
    let scene = SampleBoardScene(model: model, builder: builder)
    let coordinator: any StartViewCoordination = StartSceneCoordinator(sampleScene: scene)
    let first = try #require(
      coordinator.makeSampleViewController() as? SampleBoardViewController)
    let second = try #require(
      coordinator.makeSampleViewController() as? SampleBoardViewController)
    #expect(first !== second)
    #expect(builder.models.count == 2 && builder.models.allSatisfy { $0 === model })
    #expect(builder.receivedDelegate === scene)
    #expect(first.modalPresentationStyle == .fullScreen)
    #expect(model.listenerCount == 0)
  }

  @Test func applicationStartsWithSynchronousUIKitStartController() {
    let start = AppAssembly.makeRootViewController(configuration: AppConfiguration(arguments: []))
    start.loadViewIfNeeded()
    #expect(start.presentedViewController == nil && start.children.isEmpty)
    #expect(start.tabBarController == nil)
  }

  @Test func weakDelegateReceivesControllerIdentityAndDoesNotRetainHost() {
    var delegate: Delegate? = Delegate()
    let controller = SampleBoardViewController(
      viewModel: SampleBoardViewModel(agent: TestSampleAgent()), delegate: delegate)
    controller.requestClose()
    controller.requestSave()
    #expect(delegate?.closingController === controller)
    #expect(delegate?.savingSampleController === controller)
    delegate = nil
    #expect(controller.delegate == nil)
    controller.requestClose()
    controller.requestSave()
  }

  @Test func assemblyHostsGenericEditorWithoutStartingInjectedModel() throws {
    let model = CompositeSampleModel(loadDelay: 0.01, itemDelay: 0.01, metricInterval: 0)
    let delegate = Delegate()
    let controller = SampleBoardAssembly().makeViewController(model: model, delegate: delegate)
    #expect(model.listenerCount == 0 && !model.isActive)
    controller.loadViewIfNeeded()
    typealias Model = SampleBoardViewModel<SampleAgent>
    typealias Content = SampleBoardView<Model, Model>
    let host = try #require(controller.children.first as? UIHostingController<Content>)
    #expect(host.parent === controller && host.view.superview === controller.view)
    #expect(host.rootView.actions === host.rootView.state)
    let viewModel = host.rootView.state
    controller.loadViewIfNeeded()
    #expect(host.rootView.state === viewModel)
    #expect(controller.isModalInPresentation && controller.delegate === delegate)
  }

  @Test func controllerRetainsInjectedViewModelUntilItIsReleased() async throws {
    var viewModel: SampleBoardViewModel<TestSampleAgent>? =
      SampleBoardViewModel(agent: TestSampleAgent())
    weak let weakViewModel = viewModel
    var controller: SampleBoardViewController? = SampleBoardViewController(
      viewModel: try #require(viewModel))
    weak let weakController = controller
    viewModel = nil
    #expect(controller != nil && weakViewModel != nil)
    controller = nil
    let deadline = ContinuousClock.now + .seconds(2)
    while (weakController != nil || weakViewModel != nil) && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(weakController == nil && weakViewModel == nil)
  }
}
