import Foundation
@testable import AirhandCoreLogic

/// 和 Rust、TypeScript、Kotlin 共用的协议样例（crates/airhand-link/tests/protocol.json）：iOS 的解析和拼法对不上就失败
final class ProtocolTests {
    private static let fixture: JSON = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../crates/airhand-link/tests/protocol.json")
        return Json.parse(try! Data(contentsOf: url))!
    }()

    private func hex(_ s: String) -> Data {
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    /// 两个 JSON 值相等（字典不看键的顺序，数字不看类型）
    private func same(_ a: Any, _ b: Any) -> Bool {
        let opts: JSONSerialization.WritingOptions = [.sortedKeys]
        let da = try! JSONSerialization.data(withJSONObject: ["v": a], options: opts)
        let db = try! JSONSerialization.data(withJSONObject: ["v": b], options: opts)
        return NSDictionary(dictionary: Json.parse(da)!) == NSDictionary(dictionary: Json.parse(db)!)
    }

    func testMediaPackets() {
        let samples = (Self.fixture["media"] as! [Any]).compactMap { $0 as? JSON }
        expect(!(samples.isEmpty))
        for s in samples {
            let name = s.str("name") ?? "?"
            let data = hex(s.str("hex")!)
            data.withUnsafeBytes { b in
                expect((Int(Media.kind(b))) == (s.int("kind")))
                let payload = Data(b[Media.headerLen(b)...])
                expect((payload) == (hex(s.str("payload") ?? "")))
                switch Media.kind(b) {
                case Media.video:
                    let v = Media.video(b)!
                    expect((Int(v.seq)) == (s.int("seq")))
                    expect((v.key) == (s.bool("key")))
                    expect((v.codec.wire) == (s.str("codec")))
                    expect((v.width) == (s.int("width")))
                    expect((v.height) == (s.int("height")))
                    expect((v.captureUs) == ((s["captureUs"] as! NSNumber).int64Value))
                case Media.audio:
                    expect((Int(Media.seq(b))) == (s.int("seq")))
                    expect((b[1] & 1 != 0) == (s.bool("start")))
                    expect((Int64(bitPattern: Media.u64(b, 16))) == ((s["captureUs"] as! NSNumber).int64Value))
                case Media.cursor:
                    let c = Media.cursor(b)
                    expect((c.visible) == (s.bool("visible")))
                    expect((c.slot) == (s.int("slot")))
                    expect((c.cached) == (s.bool("cached")))
                    expect((c.inFrame) == (s.bool("inFrame")))
                    if let shape = s.obj("shape") {
                        expect((c.shape?.w) == (shape.int("width")))
                        expect((c.shape?.h) == (shape.int("height")))
                        expect((c.shape?.hx) == (shape.int("hotX")))
                        expect((c.shape?.hy) == (shape.int("hotY")))
                    } else {
                        expect((c.shape) == nil)
                    }
                default:
                    recordFailure("unknown kind in \(name)")
                }
            }
        }
    }

    func testMicPacketRoundTrips() {
        let p = Media.audioPacket(seq: 3, start: true, captureUs: 123_456_809_012, opus: Data([0xfc, 0xff, 0xfe]))
        let audio = (Self.fixture["media"] as! [Any]).compactMap { $0 as? JSON }.first { $0.str("name") == "audio" }!
        expect((p) == (hex(audio.str("hex")!)))
    }

    func testInputEvents() {
        let mine: [JSON] = [
            Input.move(0.5, 0.25), Input.delta(-3, 7), Input.button("right", true), Input.wheel(0, -120), Input.key("KeyA", false),
            Input.text("你好"), Input.releaseAll(), Input.touch(1, "down", 0.25, 0.75), Input.system(.back),
        ]
        let theirs = Self.fixture["input"] as! [Any]
        expect((mine.count) == (theirs.count))
        for (a, b) in zip(mine, theirs) { expect(same(a, b)) }
    }

    func testCommands() {
        let theirs = (Self.fixture["commands"] as! [Any]).compactMap { $0 as? JSON }
        func find(_ cmd: String) -> JSON { theirs.first { $0.str("cmd") == cmd }! }
        expect(same(Commands.input(3, [Input.delta(1, 2), Input.releaseAll()]), find("input")))
        expect(same(Commands.settings(3, Quality(fps: 60, kbps: 8000, maxShort: 1080, adaptive: true, codec: .h265)), find("settings")))
        expect(same(Commands.keyframe(3), find("keyframe")))
        expect(same(Commands.display(3, 1), find("display")))
        expect(same(Commands.audio(3, true), find("audio")))
        expect(same(Commands.mic(3, true), find("mic")))
        expect(same(Commands.clipboard(3, "hi"), find("clipboard")))
    }

    func testConnectOptions() {
        let o = Self.fixture.obj("connectOptions")!
        let s = o.obj("settings")!
        let q = Quality(fps: s.int("fps")!, kbps: s.int("bitrateKbps")!, maxShort: s.int("maxShort")!, adaptive: s.bool("adaptive"),
                        codec: Codec.fromWire(s.str("codec"))!)
        let resume = Resume.fromJson(o.arr("resume"))
        expect((resume) != nil)
        var c = Commands.connect(code: "123456", resume: resume, settings: q, hostKey: o.str("hostKey"), pairing: o.str("pairing"), audio: o.bool("audio"))
        c["cmd"] = nil
        c["code"] = nil
        expect(same(c, o))
    }

    func testCodes() {
        expect((Code.parse("123 456")) == ("123456"))
        expect((Code.parse("123-456")) == ("123456"))
        expect((Code.parse("012345")) == nil)
        expect((Code.parse("12345")) == nil)
        expect((Code.find("控制码：482 913，配对码 305127")) == ("482913"))
        expect((Code.find("1234567")) == nil)
        expect((Code.format("482913")) == ("482 913"))
    }

    func testKeyMap() {
        expect((KeyMap.code(hid: 0x04)) == ("KeyA"))
        expect((KeyMap.code(hid: 0x27)) == ("Digit0"))
        expect((KeyMap.code(hid: 0x1e)) == ("Digit1"))
        expect((KeyMap.code(hid: 0x3a)) == ("F1"))
        expect((KeyMap.code(hid: 0xe3)) == ("MetaLeft"))
        expect((KeyMap.forChar("C")?.0) == ("KeyC"))
        expect((KeyMap.forChar("?")?.1) == (true))
    }

    func testInputCoalescing() {
        var p: [JSON] = []
        Input.append(&p, Input.move(0.1, 0.1))
        Input.append(&p, Input.move(0.2, 0.2))
        Input.append(&p, Input.delta(1, 2))
        Input.append(&p, Input.delta(3, 4))
        Input.append(&p, Input.button("left", true))
        Input.append(&p, Input.delta(1, 1))
        expect((p.count) == (4))
        expect((p[0].dbl("x")) == (0.2))
        expect((p[1].int("dx")) == (4))
        expect((p[1].int("dy")) == (6))
    }
}

/// 手势：点按、双指点按、双指滚动
final class GestureTests {
    final class Out: Gestures.Out {
        var events: [String] = []
        func toRemote(_ p: CGPoint) -> CGPoint? { CGPoint(x: p.x / 1000, y: p.y / 500) }
        func contentSize() -> CGSize { CGSize(width: 1000, height: 500) }
        func move(_ nx: CGFloat, _ ny: CGFloat) { events.append("move") }
        func delta(_ nx: CGFloat, _ ny: CGFloat) { events.append("delta") }
        func button(_ b: String, _ down: Bool) { events.append("\(b)\(down ? "↓" : "↑")") }
        func wheel(_ dx: Int, _ dy: Int) { events.append("wheel") }
        func zoom(_ factor: CGFloat, _ focus: CGPoint) { events.append("zoom") }
        func pan(_ dx: CGFloat, _ dy: CGFloat) {}
        func follow() {}
        func haptic() {}
        func ripple(_ p: CGPoint) {}
        func toggleKeyboard() { events.append("keyboard") }
        func touch(_ id: Int, _ phase: String, _ nx: CGFloat, _ ny: CGFloat) { events.append("touch-\(phase)") }
    }

    func testTapIsLeftClick() {
        let o = Out()
        let g = Gestures()
        g.out = o
        g.down(.init(id: 1, x: 100, y: 100), 0)
        g.up(.init(id: 1, x: 100, y: 100), 80)
        expect((o.events.filter { $0 != "move" }) == (["left↓", "left↑"]))
    }

    func testTwoFingerTapIsRightClick() {
        let o = Out()
        let g = Gestures()
        g.out = o
        let a = Gestures.P(id: 1, x: 100, y: 100), b = Gestures.P(id: 2, x: 200, y: 100)
        g.down(a, 0)
        g.pointerDown(b, [a, b], 10)
        g.pointerUp(b, remaining: 1, 80)
        g.up(a, 90)
        expect((o.events.filter { $0 != "move" }) == (["right↓", "right↑"]))
    }

    func testTwoFingerDragScrolls() {
        let o = Out()
        let g = Gestures()
        g.out = o
        var a = Gestures.P(id: 1, x: 100, y: 100), b = Gestures.P(id: 2, x: 200, y: 100)
        g.down(a, 0)
        g.pointerDown(b, [a, b], 5)
        for i in 1...10 {
            a.y += 6; b.y += 6
            g.move([a, b], 5 + Double(i) * 16)
        }
        expect(o.events.contains("wheel"))
        expect(!(o.events.contains("left↓")))
    }

    func testMultitouchPassesFingers() {
        let o = Out()
        let g = Gestures()
        g.out = o
        g.mode = .multitouch
        let a = Gestures.P(id: 1, x: 100, y: 100)
        g.down(a, 0)
        g.move([Gestures.P(id: 1, x: 120, y: 100)], 16)
        g.up(Gestures.P(id: 1, x: 120, y: 100), 32)
        expect((o.events) == (["touch-down", "touch-move", "touch-up"]))
    }

    func testCancelReleasesAnActiveDragExactlyOnce() {
        let out = Out()
        let gestures = Gestures()
        gestures.out = out
        gestures.mode = .touch
        gestures.down(.init(id: 1, x: 100, y: 100), 0)
        gestures.move([.init(id: 1, x: 160, y: 100)], 16)
        expect(out.events.contains("left↓"))
        gestures.cancel()
        gestures.cancel()
        expect((out.events.filter { $0 == "left↑" }.count) == (1))
        expect(!(gestures.pressing))
    }

    func testCancelReleasesEveryMultitouchFinger() {
        let out = Out()
        let gestures = Gestures()
        gestures.out = out
        gestures.mode = .multitouch
        let first = Gestures.P(id: 1, x: 100, y: 100)
        let second = Gestures.P(id: 2, x: 200, y: 100)
        gestures.down(first, 0)
        gestures.pointerDown(second, [first, second], 10)
        gestures.cancel()
        gestures.cancel()
        expect((out.events.filter { $0 == "touch-down" }.count) == (2))
        expect((out.events.filter { $0 == "touch-cancel" }.count) == (2))
    }
}
