import Foundation
import Perception
@testable import AirhandCoreLogic


private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

final class StateAndTimingTests {
    func testKeyboardStickyModifiersReleaseInReverseOrder() {
        let state = KeyboardState()
        var sent: [JSON] = []
        state.send = { sent += $0 }
        state.toggle("ControlLeft")
        state.press("KeyC")
        expect((sent.compactMap { $0.str("code") }) == (["ControlLeft", "KeyC", "KeyC", "ControlLeft"]))
        expect((sent.map { $0.bool("down") }) == ([true, true, false, false]))
        expect((state.state("ControlLeft")) == (.off))
        state.toggle("ShiftLeft")
        state.toggle("ShiftLeft")
        state.press("KeyA")
        expect((state.state("ShiftLeft")) == (.locked))
        state.toggle("ShiftLeft")
        expect((state.state("ShiftLeft")) == (.off))
    }

    func testChineseCompositionIsSentAsText() {
        let state = KeyboardState()
        var sent: [JSON] = []
        state.send = { sent += $0 }
        state.text("中文输入")
        expect((sent.count) == (1))
        expect((sent.first?.str("text")) == ("中文输入"))
    }

    func testProductionStateObservationIsOneShotAndCanBeResubscribed() {
        let state = SessionUIState()
        let changes = ObservationCounter()
        func subscribe() {
            withPerceptionTracking { _ = state.hasVideo } onChange: { changes.increment() }
        }
        subscribe()
        state.hasVideo = true
        expect((changes.value) == (1))
        state.hasVideo = false
        expect((changes.value) == (1))
        subscribe()
        state.hasVideo = true
        expect((changes.value) == (2))
    }

    func testIgnoredCallbackDoesNotNotifyButKeyboardStateDoes() {
        let state = KeyboardState()
        let changes = ObservationCounter()
        withPerceptionTracking { _ = state.composing; _ = state.send } onChange: { changes.increment() }
        state.send = { _ in }
        expect((changes.value) == (0))
        state.composing = "pin"
        expect((changes.value) == (1))
    }

    func testTruncatedAndInvalidMediaHeadersAreRejected() {
        for count in 0..<Media.header {
            Data(repeating: 0, count: count).withUnsafeBytes {
                expect((Media.kind($0)) == (0))
                expect((Media.headerLen($0)) == (0))
            }
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        bytes[0] = Media.video; bytes[3] = 25
        bytes.withUnsafeBytes { expect((Media.kind($0)) == (0)) }
        bytes[3] = 24; bytes[2] = 255
        bytes.withUnsafeBytes { expect((Media.video($0)) == nil) }
    }

    func testInputsNeverCoalesceAcrossAKeyRelease() {
        var pending: [JSON] = []
        Input.append(&pending, Input.delta(1, 2))
        Input.append(&pending, Input.releaseAll())
        Input.append(&pending, Input.delta(3, 4))
        expect((pending.count) == (3))
        expect((pending[1].str("type")) == ("releaseAll"))
        expect((Input.move(-1, 2).dbl("x")) == (0))
        expect((Input.move(-1, 2).dbl("y")) == (1))
    }

    func testOldAudioGenerationCannotDelayNewSession() {
        let sync = AvSync()
        sync.setEnabled(true)
        let old = sync.reset()
        let current = sync.reset()
        sync.onAudioClock(token: old, hostUs: 0, localNs: 100_000_000, appliedMs: 0, nowNs: 0)
        expect((sync.renderTimeNs(hostUs: 0, nowNs: 0)) == (0))
        sync.onAudioClock(token: current, hostUs: 0, localNs: 100_000_000, appliedMs: 0, nowNs: 0)
        expect((sync.renderTimeNs(hostUs: 0, nowNs: 0)) == (50_000_000))
        expect((sync.renderTimeNs(hostUs: 0, nowNs: 600_000_000)) == (600_000_000))
        sync.setEnabled(false)
        expect((sync.decodeTimeNs(hostUs: 0, nowNs: 0, decodeNs: 0)) == (0))
    }

    func testJitterBufferWaitsForTargetThenProducesAudio() {
        let buffer = JitterBuffer()
        let pcm = [Int16](repeating: 1000, count: 1920)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 480)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 480)
        defer { left.deallocate(); right.deallocate() }
        pcm.withUnsafeBufferPointer { buffer.push($0, frames: 960, start: true, hostUs: 0, arrivedMs: 0) }
        expect((buffer.pull(left: left, right: right, frames: 480, finishBurst: false)) == nil)
        for index in 1..<5 {
            pcm.withUnsafeBufferPointer { buffer.push($0, frames: 960, start: false, hostUs: Int64(index) * 20_000, arrivedMs: Double(index) * 20) }
        }
        expect((buffer.pull(left: left, right: right, frames: 480, finishBurst: false)) != nil)
        expect((right[479]) > (0.02))
    }
}
