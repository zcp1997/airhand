import AirhandCore
import Foundation
import os

/// 日志：Rust 的 tracing 和 Swift 的都写进系统日志（子系统 app.airhand，Console.app 里能看到）
enum Log {
    static let logger = Logger(subsystem: "app.airhand", category: "airhand")

    static func info(_ s: String) { logger.info("\(s, privacy: .public)") }
    static func warn(_ s: String) { logger.warning("\(s, privacy: .public)") }
    static func error(_ s: String) { logger.error("\(s, privacy: .public)") }
    static func debug(_ s: String) { logger.debug("\(s, privacy: .public)") }
}

/// Rust 核心（`ios/native`，C 接口见 `ios/native/include/airhand.h`）的 Swift 包装
enum Native {
    private static let once: Void = {
        ah_init("info,quinn=warn,airhand_link::direct=info", { level, msg in
            guard let msg else { return }
            let s = String(cString: msg)
            switch level {
            case 1: Log.error(s)
            case 2: Log.warn(s)
            case 3: Log.info(s)
            default: Log.debug(s)
            }
        })
    }()

    static func initialize() { _ = once }

    /// 接管 Rust 返回的字符串
    static func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        defer { ah_string_free(p) }
        return String(cString: p)
    }

    static var protocolVersion: Int { Int(ah_protocol_version()) }

    /// 指纹合法返回 nil，否则返回原因
    static func checkFingerprint(_ fp: String) -> String? { take(ah_check_fingerprint(fp)) }

    struct StartError: Error, CustomStringConvertible { let description: String }

    // ── 控制端 ──

    static func ctlStart(_ cfg: String) throws -> Int64 {
        initialize()
        var err: UnsafeMutablePointer<CChar>?
        let h = ah_ctl_start(cfg, &err)
        if h == 0 { throw StartError(description: take(err) ?? "unknown error") }
        return h
    }

    static func ctlStop(_ h: Int64) { ah_ctl_stop(h) }
    static func ctlPollEvent(_ h: Int64, _ timeoutMs: Int32) -> String? { take(ah_ctl_poll_event(h, timeoutMs)) }
    static func ctlCall(_ h: Int64, _ json: String) -> String { take(ah_ctl_call(h, json)) ?? #"{"err":{"kind":"failed","detail":"null"}}"# }

    enum Poll { case data(Data), timeout, gone }

    /// 会话的下一条数据。Data 直接用 Rust 的内存，不再复制
    static func ctlPollSession(_ h: Int64, _ sid: UInt32, _ timeoutMs: Int32) -> Poll {
        var ptr: UnsafeMutablePointer<UInt8>?
        var len = 0
        let r = ah_ctl_poll_session(h, sid, timeoutMs, &ptr, &len)
        if r == 1, let ptr {
            return .data(Data(bytesNoCopy: ptr, count: len, deallocator: .custom { p, n in
                ah_bytes_free(p.assumingMemoryBound(to: UInt8.self), n)
            }))
        }
        return r == 0 ? .timeout : .gone
    }

    static func ctlAck(_ h: Int64, _ sid: UInt32, _ seq: UInt32) { ah_ctl_ack(h, sid, seq) }

    static func ctlMic(_ h: Int64, _ sid: UInt32, _ packet: Data) {
        packet.withUnsafeBytes { b in
            ah_ctl_mic(h, sid, b.bindMemory(to: UInt8.self).baseAddress, b.count)
        }
    }

    // ── 剪贴板里的文件 ──

    static func filesList(_ key: Int64, _ pathJson: String, recursive: Bool) -> String {
        take(ah_files_list(key, pathJson, recursive)) ?? #"{"error":"io"}"#
    }

    static func filesOpen(_ key: Int64, _ path: String, size: Int64, mtime: Int64) -> Int64 {
        ah_files_open(key, path, size, mtime)
    }

    static func filesRead(_ file: Int64, offset: Int64, into buf: UnsafeMutableRawBufferPointer) -> Int64 {
        ah_files_read(file, offset, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
    }

    static func filesClose(_ file: Int64) { ah_files_close(file) }
    static func filesReady(_ key: Int64) { ah_files_ready(key) }

    // ── 被控端 ──

    static func hostStart(_ cfg: String) throws -> Int64 {
        initialize()
        var err: UnsafeMutablePointer<CChar>?
        let h = ah_host_start(cfg, &err)
        if h == 0 { throw StartError(description: take(err) ?? "unknown error") }
        return h
    }

    static func hostStop(_ h: Int64) { ah_host_stop(h) }
    static func hostPollEvent(_ h: Int64, _ timeoutMs: Int32) -> String? { take(ah_host_poll_event(h, timeoutMs)) }
    @discardableResult static func hostCall(_ h: Int64, _ json: String) -> String? { take(ah_host_call(h, json)) }
    static func hostTick(_ h: Int64) -> String? { take(ah_host_tick(h)) }
    static func hostWaitWindow(_ h: Int64, _ timeoutMs: Int32) -> Bool { ah_host_wait_window(h, timeoutMs) }

    static func hostVideo(_ h: Int64, _ data: UnsafeRawBufferPointer, key: Bool, config: Bool, captureUs: Int64, codec: Int32, width: Int, height: Int) {
        ah_host_video(h, data.bindMemory(to: UInt8.self).baseAddress, data.count, (key ? 1 : 0) | (config ? 2 : 0),
                      captureUs, codec, Int32(width), Int32(height))
    }

    static func hostAudio(_ h: Int64, _ data: UnsafeRawBufferPointer, captureUs: Int64) {
        ah_host_audio(h, data.bindMemory(to: UInt8.self).baseAddress, data.count, captureUs)
    }
}

// ───────────────────────────── JSON ─────────────────────────────
