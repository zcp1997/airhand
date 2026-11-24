import XCTest
import Perception
@testable import Airhand


private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

final class ObservationTests: XCTestCase {
    func testKeyboardObservationAndBindingsUseProductionState() {
        let state = KeyboardState()
        let notifications = ObservationCounter()
        withPerceptionTracking { _ = state.state("ControlLeft") } onChange: { notifications.increment() }
        state.toggle("ControlLeft")
        XCTAssertEqual(notifications.value, 1)
        XCTAssertEqual(state.state("ControlLeft"), .once)
        @Perception.Bindable var binding = state
        $binding.composing.wrappedValue = "拼音"
        XCTAssertEqual(state.composing, "拼音")
    }

    func testSessionStateCanBeObservedAgainAfterNotification() {
        let state = SessionUIState()
        let notifications = ObservationCounter()
        func subscribe() {
            withPerceptionTracking { _ = state.hasVideo } onChange: { notifications.increment() }
        }
        subscribe()
        state.hasVideo = true
        subscribe()
        state.hasVideo = false
        XCTAssertEqual(notifications.value, 2)
    }
}
