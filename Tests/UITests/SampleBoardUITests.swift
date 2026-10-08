import XCTest

@MainActor
final class SampleBoardUITests: XCTestCase {
  /// Let UIKit finish the native lift animation before XCTest starts moving the pointer.
  private let nativeLiftDuration: TimeInterval = 1.2
  private func launch(liveMetrics: Bool = false, appearance: String? = nil) -> XCUIApplication {
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    if !liveMetrics { app.launchArguments.append("--disable-mock-metric-timer") }
    if let appearance { app.launchArguments.append(appearance) }
    app.launch()
    XCTAssertTrue(app.buttons["open-sample-board"].waitForExistence(timeout: 3))
    app.buttons["open-sample-board"].tap()
    XCTAssertTrue(app.buttons["card-1"].waitForExistence(timeout: 5))
    let portrait = NSPredicate { _, _ in
      app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width
    }
    expectation(for: portrait, evaluatedWith: app)
    waitForExpectations(timeout: 5)
    return app
  }

  private func enterEditMode(in app: XCUIApplication) {
    app.buttons["card-1"].press(forDuration: 0.65)
    XCTAssertTrue(app.buttons["done-editing"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.buttons["done-editing"].label, "Done")
    XCTAssertFalse(app.buttons["save-sample"].exists)
    if app.buttons["card-2"].exists {
      XCTAssertTrue(app.buttons["delete-1"].waitForExistence(timeout: 3))
    }
    XCTAssertFalse(app.textFields["field-1"].exists)
  }

  private func addCard(in app: XCUIApplication, number: Int) {
    app.buttons["add-card"].tap()
    XCTAssertTrue(app.buttons["card-\(number)"].waitForExistence(timeout: 3))
    waitForToolbarReady(in: app)
    let loaded = NSPredicate(format: "NOT (value CONTAINS %@)", "Loading")
    expectation(for: loaded, evaluatedWith: app.buttons["card-\(number)"])
    waitForExpectations(timeout: 4)
  }

  private func editFirstField(in app: XCUIApplication, number: Int, suffix: String) {
    app.buttons["card-\(number)"].tap()
    let field = app.descendants(matching: .any).matching(identifier: "field-1").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.tap()
    field.typeText(suffix)
    app.buttons["save-editor"].tap()
    XCTAssertTrue(app.buttons["card-\(number)"].waitForExistence(timeout: 3))
  }

  func testSynchronousStartPresentationAndRepeatedOpening() {
    let app = XCUIApplication()
    app.launchArguments = ["--disable-mock-metric-timer"]
    app.launch()
    XCTAssertTrue(app.buttons["open-sample-board"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    for _ in 0..<2 {
      app.buttons["open-sample-board"].tap()
      XCTAssertTrue(app.buttons["card-1"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.navigationBars["Java → Swift Lab"].exists)
      XCTAssertTrue(app.buttons["close-sample-board"].exists)
      XCTAssertTrue(app.textViews.allElementsBoundByIndex.isEmpty)
      app.buttons["close-sample-board"].tap()
      XCTAssertTrue(app.buttons["open-sample-board"].waitForExistence(timeout: 3))
      XCTAssertTrue(app.buttons["open-sample-board"].isHittable)
    }
  }

  func testLongPressDoneBackgroundTapAndSave() {
    let app = launch(appearance: "--light-appearance")
    XCTAssertTrue(app.buttons["save-sample"].exists)
    XCTAssertFalse(app.buttons["Edit"].exists)
    XCTAssertTrue(app.textViews.allElementsBoundByIndex.isEmpty)
    editFirstField(in: app, number: 1, suffix: " first")
    addCard(in: app, number: 2)
    editFirstField(in: app, number: 2, suffix: " second")
    let first = app.buttons["card-1"].value as? String
    let second = app.buttons["card-2"].value as? String
    XCTAssertFalse(app.buttons["delete-1"].exists)
    enterEditMode(in: app)
    XCTAssertTrue(app.buttons["delete-2"].exists)
    capture(app, name: "sample-edit-mode")
    app.buttons["done-editing"].tap()
    XCTAssertTrue(app.buttons["save-sample"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["delete-1"].exists)
    XCTAssertTrue(app.buttons["card-2"].exists)
    XCTAssertFalse(app.alerts["Sample saved"].exists)

    enterEditMode(in: app)
    let firstFrame = app.buttons["card-1"].frame
    let secondFrame = app.buttons["card-2"].frame
    app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: (firstFrame.midX + secondFrame.midX) / 2, dy: firstFrame.midY)
    ).tap()
    XCTAssertTrue(app.buttons["save-sample"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["delete-2"].exists)

    enterEditMode(in: app)
    let bottom = max(firstFrame.maxY, secondFrame.maxY)
    app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: app.frame.midX, dy: (bottom + app.windows.firstMatch.frame.maxY - 30) / 2)
    ).tap()
    XCTAssertTrue(app.buttons["save-sample"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["delete-2"].exists)

    enterEditMode(in: app)
    app.buttons["card-1"].tap()
    XCTAssertTrue(app.textFields["field-1"].waitForExistence(timeout: 3))
    app.buttons["cancel-editor"].tap()
    XCTAssertTrue(app.buttons["done-editing"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["delete-1"].exists)
    app.buttons["card-1"].press(
      forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-2"],
      withVelocity: .slow, thenHoldForDuration: 0.3)
    assertArrangement(in: app, first: second, second: first)
    app.buttons["delete-2"].tap()
    XCTAssertFalse(app.buttons["card-2"].exists)
    XCTAssertFalse(app.buttons["delete-1"].exists)
    waitForToolbarReady(in: app)
    app.buttons["done-editing"].tap()
    XCTAssertTrue(app.buttons["save-sample"].waitForExistence(timeout: 3))
    app.buttons["save-sample"].tap()
    let alert = app.alerts["Sample saved"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["open-sample-board"].exists)
    capture(app, name: "sample-saved-alert")
    alert.buttons["OK"].tap()
    app.buttons["open-sample-board"].tap()
    XCTAssertTrue(app.buttons["card-1"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.buttons["card-1"].value as? String, second)
    XCTAssertFalse(app.buttons["delete-1"].exists)
    capture(app, name: "sample-reopened")
  }


  func testCopyIsIndependentAndLastCardIsProtected() {
    let app = launch()
    let original = app.buttons["card-1"].value as? String
    addCard(in: app, number: 2)
    XCTAssertEqual(withoutRuntime(app.buttons["card-2"].value as? String), withoutRuntime(original))
    editFirstField(in: app, number: 2, suffix: " edited")
    XCTAssertEqual(app.buttons["card-1"].value as? String, original)
    XCTAssertNotEqual(app.buttons["card-2"].value as? String, original)
    enterEditMode(in: app)
    app.buttons["delete-1"].tap()
    XCTAssertFalse(app.buttons["card-2"].exists)
    XCTAssertFalse(app.buttons["delete-1"].exists)
    XCTAssertTrue(app.buttons["add-card"].exists)
  }

  func testInitialLoadingPendingCardAndLiveMetrics() {
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments.append("--slow-mock-initial-load")
    app.launch()
    XCTAssertTrue(app.buttons["open-sample-board"].waitForExistence(timeout: 3))
    app.buttons["open-sample-board"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "board-loading")
        .firstMatch.waitForExistence(timeout: 2))
    capture(app, name: "initial-loading")
    XCTAssertTrue(app.buttons["card-1"].waitForExistence(timeout: 5))
    let original = app.buttons["card-1"].value as? String
    let metricChanged = NSPredicate { _, _ in app.buttons["card-1"].value as? String != original }
    expectation(for: metricChanged, evaluatedWith: app)
    waitForExpectations(timeout: 6)
    app.buttons["add-card"].tap()
    XCTAssertTrue(app.buttons["card-2"].waitForExistence(timeout: 2))
    XCTAssertEqual(app.buttons["card-2"].value as? String, "Loading…")
    capture(app, name: "item-loading")
    let loaded = NSPredicate(format: "NOT (value CONTAINS %@)", "Loading")
    expectation(for: loaded, evaluatedWith: app.buttons["card-2"])
    waitForExpectations(timeout: 4)
    capture(app, name: "live-samples")
  }

  func testOneHeldGestureEntersEditModeAndReorders() {
    let app = launch()
    editFirstField(in: app, number: 1, suffix: " first")
    addCard(in: app, number: 2)
    editFirstField(in: app, number: 2, suffix: " second")
    let firstValue = app.buttons["card-1"].value as? String
    let secondValue = app.buttons["card-2"].value as? String
    app.buttons["card-1"].press(forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-2"])
    assertArrangement(in: app, first: secondValue, second: firstValue)
    XCTAssertEqual(app.buttons["done-editing"].label, "Done")
    XCTAssertTrue(app.buttons["delete-1"].exists)
  }

  func testHoverPreviewAndAcceptedDrop() {
    let app = launch(appearance: "--light-appearance")
    editFirstField(in: app, number: 1, suffix: " first")
    addCard(in: app, number: 2)
    editFirstField(in: app, number: 2, suffix: " second")
    let first = app.buttons["card-1"].value as? String
    let second = app.buttons["card-2"].value as? String
    capture(app, name: "hover-before")
    // The end hold also permits an external simulator capture before the pointer is released.
    print("HOVER_PREVIEW_CAPTURE_START")
    app.buttons["card-1"].press(
      forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-2"],
      withVelocity: .slow, thenHoldForDuration: 4)
    assertArrangement(in: app, first: second, second: first)
    XCTAssertTrue(app.buttons["done-editing"].isEnabled)
    capture(app, name: "hover-after-drop")
  }

  func testSystemDragCancellationAndRepeatedMove() {
    let app = launch()
    selectLayout(in: app, id: "sequence")
    editFirstField(in: app, number: 1, suffix: " first")
    addCard(in: app, number: 2)
    editFirstField(in: app, number: 2, suffix: " second")
    let first = app.buttons["card-1"].value as? String
    let second = app.buttons["card-2"].value as? String
    let source = app.buttons["card-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let target = app.buttons["card-2"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let empty = app.buttons["add-card"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    source.press(
      forDuration: nativeLiftDuration, thenDragTo: target, withVelocity: .slow,
      thenHoldForDuration: 0.3)
    assertArrangement(in: app, first: second, second: first)
    // Crossing an occupied card must not change the sample if the gesture ends on the add tile.
    source.press(
      forDuration: nativeLiftDuration, thenDragTo: empty, withVelocity: .slow,
      thenHoldForDuration: 0.3)
    assertArrangement(in: app, first: second, second: first)
    XCTAssertTrue(app.buttons["done-editing"].isEnabled)
    source.press(
      forDuration: nativeLiftDuration, thenDragTo: target, withVelocity: .slow,
      thenHoldForDuration: 0.3)
    assertArrangement(in: app, first: first, second: second)
    // A cancelled drag outside the grid cannot leave a command or visual lock behind.
    source.press(
      forDuration: nativeLiftDuration,
      thenDragTo: app.buttons["layout-picker"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
      withVelocity: .slow, thenHoldForDuration: 0.3)
    assertArrangement(in: app, first: first, second: second)
    app.buttons["done-editing"].tap()
    XCTAssertTrue(app.buttons["save-sample"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.textFields["field-1"].exists)
  }

  func testLeadingCardMovesBothWaysAndCanBeDeleted() {
    let app = launch()
    editFirstField(in: app, number: 1, suffix: " first")
    addCard(in: app, number: 2)
    editFirstField(in: app, number: 2, suffix: " second")
    let first = app.buttons["card-1"].value as? String
    let second = app.buttons["card-2"].value as? String
    for layout in ["staged-radial", "staged-matrix"] {
      selectLayout(in: app, id: "\(layout)")
      // A brief hold lets UIKit resolve the native drop destination.
      app.buttons["card-1"].press(
        forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-2"],
        withVelocity: .slow, thenHoldForDuration: 0.3)
      assertArrangement(in: app, first: second, second: first)
      app.buttons["card-2"].press(
        forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-1"],
        withVelocity: .slow, thenHoldForDuration: 0.3)
      assertArrangement(in: app, first: first, second: second)
    }
    app.buttons["delete-1"].tap()
    XCTAssertEqual(app.buttons["card-1"].value as? String, second)
    XCTAssertFalse(app.buttons["delete-1"].exists)
  }

  func testCenteredInitialAddAndRuntimeEditor() {
    let app = launch()
    selectLayout(in: app, id: "staged-matrix")
    XCTAssertEqual(
      app.buttons["add-card"].frame.midX, app.buttons["card-1"].frame.midX, accuracy: 1)
    addCard(in: app, number: 2)
    XCTAssertLessThan(app.buttons["card-2"].frame.midX, app.buttons["add-card"].frame.midX)
    app.buttons["card-1"].tap()
    app.segmentedControls["sample-runtime"].buttons["SWIFT"].tap()
    app.buttons["save-editor"].tap()
    XCTAssertTrue((app.buttons["card-1"].value as? String)?.contains("SWIFT") == true)
    capture(app, name: "SWIFT-card")
  }

  func testGridPlacementAndReorderAcrossRows() {
    let app = launch(appearance: "--light-appearance")
    for number in 2...4 { addCard(in: app, number: number) }
    editFirstField(in: app, number: 1, suffix: " first")
    editFirstField(in: app, number: 4, suffix: " fourth")
    let values = (1...4).map { app.buttons["card-\($0)"].value as? String }
    for layout in ["staged-radial", "sequence", "radial", "matrix", "staged-matrix"] {
      selectLayout(in: app, id: layout)
      let frames = (1...4).map { app.buttons["card-\($0)"].frame }
      assertSquareNonOverlappingCards(frames)
      XCTAssertNotEqual(frames[0].midY, frames[3].midY)
      app.buttons["card-1"].press(
        forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-4"],
        withVelocity: .slow, thenHoldForDuration: 0.3)
      assertCardValues(in: app, values: Array(values.dropFirst()) + [values[0]])
      capture(app, name: "grid-\(layout)-cross-row")
      app.buttons["card-4"].press(
        forDuration: nativeLiftDuration, thenDragTo: app.buttons["card-1"],
        withVelocity: .slow, thenHoldForDuration: 0.3)
      assertCardValues(in: app, values: values)
    }
  }

  func testCapacityAcrossLayoutsAndCaptureAppearance() {
    let app = launch()
    replaceIterations(in: app, number: 1, value: "+1,234,567,890")
    addCard(in: app, number: 2)
    replaceIterations(in: app, number: 2, value: "-1,234,567,890")
    for number in 3...8 { addCard(in: app, number: number) }
    let values = (1...8).map { app.buttons["card-\($0)"].value as? String }
    for layout in ["staged-radial", "sequence", "radial", "matrix", "staged-matrix"] {
      selectLayout(in: app, id: "\(layout)")
      XCTAssertFalse(app.buttons["add-card"].exists)
      XCTAssertFalse(app.buttons["card-9"].exists)
      for number in 1...8 {
        XCTAssertEqual(app.buttons["card-\(number)"].value as? String, values[number - 1])
      }
      let frames = (1...8).map { app.buttons["card-\($0)"].frame }
      assertSquareNonOverlappingCards(frames)
      capture(app, name: "\(layout)-full")
    }
    enterEditMode(in: app)
    XCTAssertTrue(app.buttons["delete-1"].exists)
    capture(app, name: "staged-matrix-editing")
    XCUIDevice.shared.orientation = .landscapeLeft
    let landscape = NSPredicate { _, _ in
      app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
    }
    expectation(for: landscape, evaluatedWith: app)
    waitForExpectations(timeout: 5)
    app.scrollViews.firstMatch.swipeDown()
    let first = app.buttons["card-1"].frame
    XCTAssertEqual(first.width, first.height, accuracy: 1)
    XCTAssertTrue(app.windows.firstMatch.frame.contains(first))
    capture(app, name: "staged-matrix-landscape")
  }

  func testNativeDragAutoscrollsInLandscapeAndCancellationKeepsArrangement() {
    let app = launch()
    selectLayout(in: app, id: "staged-radial")
    for number in 2...8 { addCard(in: app, number: number) }
    let values = (1...8).map { app.buttons["card-\($0)"].value as? String }
    XCUIDevice.shared.orientation = .landscapeLeft
    let landscape = NSPredicate { _, _ in
      app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
    }
    expectation(for: landscape, evaluatedWith: app)
    waitForExpectations(timeout: 5)
    app.scrollViews.firstMatch.swipeDown()
    let first = app.buttons["card-1"].frame
    let viewport = app.scrollViews.firstMatch.frame
    let bottomEdge = app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: viewport.midX, dy: viewport.maxY - 8))
    app.buttons["card-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
      forDuration: nativeLiftDuration, thenDragTo: bottomEdge,
      withVelocity: .slow, thenHoldForDuration: 2)
    XCTAssertLessThan(app.buttons["card-1"].frame.minY, first.minY - 30)
    assertCardValues(in: app, values: values)
    capture(app, name: "native-drag-autoscroll-landscape")
  }

  func testValidationBannerFollowsErrorsInBothThemes() {
    for appearance in ["--light-appearance", "--dark-appearance"] {
      let app = launch(appearance: appearance)
      addCard(in: app, number: 2)
      let first = app.buttons["card-1"]
      let second = app.buttons["card-2"]
      let banner = app.descendants(matching: .any).matching(identifier: "sample-error").firstMatch
      XCTAssertFalse(banner.exists)
      replaceMetric(in: app, number: 2, value: "0")
      XCTAssertTrue(banner.waitForExistence(timeout: 3))
      XCTAssertFalse(app.buttons["save-sample"].isEnabled)
      XCTAssertTrue(banner.label.contains("Metric must be a positive number."))
      XCTAssertLessThanOrEqual(banner.frame.maxY, app.buttons["layout-picker"].frame.minY + 1)
      XCTAssertFalse((first.value as? String)?.contains("Validation error") == true)
      XCTAssertTrue((second.value as? String)?.contains("Validation error") == true)
      capture(app, name: "validation-error-\(appearance)")

      enterEditMode(in: app)
      XCTAssertTrue(app.buttons["delete-2"].waitForExistence(timeout: 3))
      XCTAssertTrue(app.buttons["delete-2"].isHittable)
      XCTAssertTrue((second.value as? String)?.contains("Validation error") == true)
      capture(app, name: "validation-error-edit-mode-\(appearance)")
      XCTAssertTrue(app.buttons["done-editing"].isEnabled)
      app.buttons["done-editing"].tap()
      XCTAssertTrue(app.buttons["save-sample"].waitForExistence(timeout: 3))
      XCTAssertFalse(app.buttons["save-sample"].isEnabled)
      XCTAssertFalse(app.buttons["delete-2"].exists)
      XCTAssertTrue(banner.exists)
      XCTAssertTrue((second.value as? String)?.contains("Validation error") == true)
      enterEditMode(in: app)
      replaceMetric(in: app, number: 2, value: "42.00")
      let gone = NSPredicate(format: "exists == false")
      expectation(for: gone, evaluatedWith: banner)
      waitForExpectations(timeout: 3)
      XCTAssertFalse((second.value as? String)?.contains("Validation error") == true)

      replaceMetric(in: app, number: 2, value: "0")
      XCTAssertTrue(banner.waitForExistence(timeout: 3))
      enterEditMode(in: app)
      app.buttons["delete-2"].tap()
      expectation(for: gone, evaluatedWith: banner)
      waitForExpectations(timeout: 3)
      XCTAssertFalse(second.exists)
      XCTAssertFalse((first.value as? String)?.contains("Validation error") == true)
      app.terminate()
    }
  }

  private func replaceMetric(in app: XCUIApplication, number: Int = 1, value: String) {
    app.buttons["card-\(number)"].tap()
    let field = app.descendants(matching: .any).matching(identifier: "field-4").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    let previous = field.value as? String ?? ""
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
    app.buttons["save-editor"].tap()
    XCTAssertTrue(app.buttons["card-\(number)"].waitForExistence(timeout: 3))
  }

  /// iOS 26 reports a SwiftUI Menu as a legacy Button and a modern PopUpButton.
  /// Use its visible center instead of the unreliable accessibility hit point after rotation.
  private func selectLayout(in app: XCUIApplication, id: String) {
    let picker = app.descendants(matching: .any).matching(identifier: "layout-picker").firstMatch
    XCTAssertTrue(picker.waitForExistence(timeout: 3))
    XCTAssertTrue(app.windows.firstMatch.frame.contains(picker.frame))
    picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let item = app.buttons["layout-\(id)"]
    XCTAssertTrue(item.waitForExistence(timeout: 3))
    item.tap()
    let selected = NSPredicate(format: "value == %@", LayoutTitle.forID(id))
    expectation(for: selected, evaluatedWith: picker)
    waitForExpectations(timeout: 3)
    let ready = NSPredicate(format: "enabled == true")
    expectation(for: ready, evaluatedWith: picker)
    waitForExpectations(timeout: 3)
  }

  private enum LayoutTitle {
    static func forID(_ id: String) -> String {
      switch id {
      case "staged-radial": "Staged radial"
      case "sequence": "Sequence"
      case "radial": "Radial"
      case "matrix": "Matrix"
      case "staged-matrix": "Staged matrix"
      default: id
      }
    }
  }

  private func assertSquareNonOverlappingCards(_ frames: [CGRect]) {
    for (index, frame) in frames.enumerated() {
      XCTAssertGreaterThan(frame.width, 0)
      XCTAssertEqual(frame.width, frame.height, accuracy: 1)
      for other in frames.dropFirst(index + 1) {
        XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0.5).intersects(other))
      }
    }
  }

  private func assertCardValues(in app: XCUIApplication, values: [String?]) {
    let confirmed = NSPredicate { _, _ in
      values.enumerated().allSatisfy { index, value in
        app.buttons["card-\(index + 1)"].value as? String == value
      }
    }
    expectation(for: confirmed, evaluatedWith: app)
    waitForExpectations(timeout: 4)
    waitForToolbarReady(in: app)
    XCTAssertTrue(confirmed.evaluate(with: app))
  }

  private func assertArrangement(in app: XCUIApplication, first: String?, second: String?) {
    let confirmed = NSPredicate { _, _ in
      app.buttons["card-1"].value as? String == first
        && app.buttons["card-2"].value as? String == second
    }
    expectation(for: confirmed, evaluatedWith: app)
    waitForExpectations(timeout: 4)
    // Wait for the source command as well as the native drop gesture.
    waitForToolbarReady(in: app)
    XCTAssertEqual(app.buttons["card-1"].value as? String, first)
    XCTAssertEqual(app.buttons["card-2"].value as? String, second)
  }

  private func waitForToolbarReady(in app: XCUIApplication) {
    let ready = NSPredicate { _, _ in
      let action = app.buttons["done-editing"].exists
        ? app.buttons["done-editing"] : app.buttons["save-sample"]
      return action.exists && action.isEnabled
    }
    expectation(for: ready, evaluatedWith: app)
    waitForExpectations(timeout: 4)
  }

  private func withoutRuntime(_ value: String?) -> String? {
    value?.replacingOccurrences(of: "Runtime: JAVA", with: "Runtime")
      .replacingOccurrences(of: "Runtime: SWIFT", with: "Runtime")
  }

  private func replaceIterations(in app: XCUIApplication, number: Int, value: String) {
    app.buttons["card-\(number)"].tap()
    let field = app.descendants(matching: .any).matching(identifier: "field-3").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    let previous = field.value as? String ?? ""
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
    app.buttons["save-editor"].tap()
    XCTAssertTrue(
      (app.buttons["card-\(number)"].value as? String)?.contains("Iterations: \(value),") == true)
  }

  private func capture(_ app: XCUIApplication, name: String) {
    // Capture the display so window cropping does not use stale portrait coordinates after rotation.
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
