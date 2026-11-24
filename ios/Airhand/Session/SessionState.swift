import Foundation
import Perception

/// 软键盘上面那一排特殊键的状态：修饰键是“粘滞”的——点一下只对下一个键有效，再点一下锁定，再点取消
@Perceptible
final class KeyboardState {
    enum Sticky { case off, once, locked }
    static let mods = ["ControlLeft", "AltLeft", "ShiftLeft", "MetaLeft"]
    var mods: [String: Sticky] = [:]
    var composing = ""
    @PerceptionIgnored var send: ([JSON]) -> Void = { _ in }

    func state(_ m: String) -> Sticky { mods[m] ?? .off }

    func toggle(_ m: String) {
        switch state(m) {
        case .off: mods[m] = .once
        case .once: mods[m] = .locked
        case .locked: mods[m] = .off
        }
    }

    private var active: [String] { Self.mods.filter { state($0) != .off } }

    private func consumeOnce() {
        for m in Self.mods where state(m) == .once { mods[m] = .off }
    }

    /// 按一个键（带上按着的修饰键）
    func press(_ code: String, shift: Bool = false) {
        var chord = active
        if shift && !chord.contains("ShiftLeft") { chord.append("ShiftLeft") }
        send(Input.chord(chord + [code]))
        consumeOnce()
    }

    func chord(_ codes: [String]) { send(Input.chord(codes)) }

    /// 软键盘打的字：没有修饰键时按文字发（输入法打的中文也行），有修饰键时按键发（Ctrl + C 这样的）
    func text(_ s: String) {
        let mods = active
        if mods.isEmpty || mods == ["ShiftLeft"] && s.count > 1 {
            send([Input.text(s)])
            consumeOnce()
            return
        }
        for ch in s {
            if let (code, shift) = KeyMap.forChar(ch) { press(code, shift: shift) } else { send([Input.text(String(ch))]) }
        }
    }
}

/// 远程画面上界面层的状态（SwiftUI 部分观察）
@Perceptible
final class SessionUIState {
    var hasVideo = false
    /// 菜单里选的操作方式（电脑）：trackpad / touch；nil = 按设置
    var mode: String?
    var effectiveMode = "trackpad"
}

