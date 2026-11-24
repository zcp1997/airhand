import Foundation

private var assertionFailures = 0
func recordFailure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    assertionFailures += 1
    fputs("FAIL: \(file):\(line): \(message)\n", stderr)
}
func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition() { recordFailure("Expectation was false", file: file, line: line) }
}
if CommandLine.arguments.contains("--probe-failure") {
    expect(false)
    exit(assertionFailures == 0 ? 0 : 1)
}
let cases: [(String, () -> Void)] = [
    ("ProtocolTests.testMediaPackets", { ProtocolTests().testMediaPackets() }),
    ("ProtocolTests.testMicPacketRoundTrips", { ProtocolTests().testMicPacketRoundTrips() }),
    ("ProtocolTests.testInputEvents", { ProtocolTests().testInputEvents() }),
    ("ProtocolTests.testCommands", { ProtocolTests().testCommands() }),
    ("ProtocolTests.testConnectOptions", { ProtocolTests().testConnectOptions() }),
    ("ProtocolTests.testCodes", { ProtocolTests().testCodes() }),
    ("ProtocolTests.testKeyMap", { ProtocolTests().testKeyMap() }),
    ("ProtocolTests.testInputCoalescing", { ProtocolTests().testInputCoalescing() }),
    ("GestureTests.testTapIsLeftClick", { GestureTests().testTapIsLeftClick() }),
    ("GestureTests.testTwoFingerTapIsRightClick", { GestureTests().testTwoFingerTapIsRightClick() }),
    ("GestureTests.testTwoFingerDragScrolls", { GestureTests().testTwoFingerDragScrolls() }),
    ("GestureTests.testMultitouchPassesFingers", { GestureTests().testMultitouchPassesFingers() }),
    ("GestureTests.testCancelReleasesAnActiveDragExactlyOnce", { GestureTests().testCancelReleasesAnActiveDragExactlyOnce() }),
    ("GestureTests.testCancelReleasesEveryMultitouchFinger", { GestureTests().testCancelReleasesEveryMultitouchFinger() }),
    ("StateAndTimingTests.testKeyboardStickyModifiersReleaseInReverseOrder", { StateAndTimingTests().testKeyboardStickyModifiersReleaseInReverseOrder() }),
    ("StateAndTimingTests.testChineseCompositionIsSentAsText", { StateAndTimingTests().testChineseCompositionIsSentAsText() }),
    ("StateAndTimingTests.testProductionStateObservationIsOneShotAndCanBeResubscribed", { StateAndTimingTests().testProductionStateObservationIsOneShotAndCanBeResubscribed() }),
    ("StateAndTimingTests.testIgnoredCallbackDoesNotNotifyButKeyboardStateDoes", { StateAndTimingTests().testIgnoredCallbackDoesNotNotifyButKeyboardStateDoes() }),
    ("StateAndTimingTests.testTruncatedAndInvalidMediaHeadersAreRejected", { StateAndTimingTests().testTruncatedAndInvalidMediaHeadersAreRejected() }),
    ("StateAndTimingTests.testInputsNeverCoalesceAcrossAKeyRelease", { StateAndTimingTests().testInputsNeverCoalesceAcrossAKeyRelease() }),
    ("StateAndTimingTests.testOldAudioGenerationCannotDelayNewSession", { StateAndTimingTests().testOldAudioGenerationCannotDelayNewSession() }),
    ("StateAndTimingTests.testJitterBufferWaitsForTargetThenProducesAudio", { StateAndTimingTests().testJitterBufferWaitsForTargetThenProducesAudio() }),
 ]
precondition(cases.count == 22 && Set(cases.map { $0.0 }).count == 22)
var passed = 0
for (name, run) in cases {
    let before = assertionFailures
    run()
    if assertionFailures == before { passed += 1; print("PASS: \(name)") }
}
print("Core self-test result: \(passed)/\(cases.count) passed; \(assertionFailures) assertion failures")
exit(assertionFailures == 0 && passed == cases.count ? 0 : 1)
