import Foundation

typealias JSON = [String: Any]

enum Json {
    static func parse(_ s: String) -> JSON? {
        guard let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? JSON
    }

    static func parse(_ d: Data) -> JSON? { (try? JSONSerialization.jsonObject(with: d)) as? JSON }

    static func string(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o),
              let d = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    static func encode<T: Encodable>(_ v: T) -> String {
        guard let d = try? JSONEncoder().encode(v) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue }
    func dbl(_ k: String) -> Double? { (self[k] as? NSNumber)?.doubleValue }
    func bool(_ k: String) -> Bool { (self[k] as? NSNumber)?.boolValue ?? false }
    func obj(_ k: String) -> JSON? { self[k] as? JSON }
    func arr(_ k: String) -> [Any]? { self[k] as? [Any] }
    func strings(_ k: String) -> [String] { (self[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
}

/// 单调时钟（纳秒，mach_absolute_time，和 CoreAudio、CoreMedia 的主机时钟同源）
enum Clock {
    private static let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()

    static var nowNs: Int64 { Int64(DispatchTime.now().uptimeNanoseconds) }
    static var nowMs: Double { Double(nowNs) / 1e6 }

    static func hostTimeToNs(_ t: UInt64) -> Int64 {
        Int64(Double(t) * Double(timebase.numer) / Double(timebase.denom))
    }
}

func hexString(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
