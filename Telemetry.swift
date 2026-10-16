// Anonymous usage statistics via TelemetryDeck (https://telemetrydeck.com), no SDK needed.
// What is sent: app version, macOS version, CPU architecture, UI language, number of external
// displays, and which WakeDisplay feature was used. Never: names, files, IP-derived identity,
// display serials or anything personal. The user ID is a salted SHA-256 of a random install UUID.
// Users can switch it off in About ▸ Privacy ▸ "Send Anonymous Usage Stats".
//
// 匿名使用统计（TelemetryDeck）：只发送版本号、系统版本、芯片架构、界面语言、外接屏数量和用了哪个功能。
// 不发送任何个人信息；用户标识是随机安装 ID 的加盐 SHA-256。在「关于」窗口里可一键关闭。
import Foundation
import CommonCrypto   // libSystem: no extra framework to load at launch

enum Telemetry {
    static let appID = "D903CDC5-259C-4503-ABD2-C1E8375A342C"
    static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/namespace/com.big2/")!
    static let sessionID = UUID().uuidString

    /// On by default; the menu toggle stores false to opt out
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "telemetryEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "telemetryEnabled") }
    }

    /// Stable anonymous user hash: random per-install UUID, salted and hashed
    static let clientUser: String = {
        let d = UserDefaults.standard
        let id: String
        if let saved = d.string(forKey: "telemetryInstallID") { id = saved }
        else { id = UUID().uuidString; d.set(id, forKey: "telemetryInstallID") }
        let bytes = Array(("WakeDisplay.v1:" + id).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(bytes, CC_LONG(bytes.count), &digest)        // same hash as before → same anonymous ID
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static func send(_ type: String, _ extra: [String: String] = [:]) {
        guard enabled else { return }
        post(type, extra)
    }

    /// For crash reports, which have their own switch (About ▸ Privacy ▸ Send Crash Reports)
    static func sendAlways(_ type: String, _ extra: [String: String] = [:]) { post(type, extra) }

    private static func post(_ type: String, _ extra: [String: String]) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var payload: [String: Any] = [
            "App.version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            "System.macOSVersion": "\(v.majorVersion).\(v.minorVersion)",
            "System.architecture": architecture,
            "App.language": effectiveLang().rawValue,
            "Displays.externalCount": physicalExternals().count,
        ]
        for (k, val) in extra { payload[k] = val }
        let body: [[String: Any]] = [[
            "appID": appID,
            "clientUser": clientUser,
            "sessionID": sessionID,
            "type": type,
            "payload": payload,
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 15
        net.dataTask(with: req).resume()   // fire-and-forget; failures are ignored
    }

    /// Feature usage: Feature.used with Feature.name / Feature.source
    static func feature(_ name: String, source: String = "menu") {
        send("Feature.used", ["Feature.name": name, "Feature.source": source])
    }

    /// One "App.dailyActive" per calendar day, so long-running sessions still count as active users
    static func dailyActiveIfNeeded() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let d = UserDefaults.standard
        guard d.string(forKey: "telemetryLastDay") != today else { return }
        d.set(today, forKey: "telemetryLastDay")
        send("App.dailyActive")
    }
}

// MARK: - Lightweight shared helpers

/// Cache-free network session: no in-memory/on-disk URL cache, one connection per host.
let net: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.urlCache = nil
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.httpMaximumConnectionsPerHost = 1
    return URLSession(configuration: c)
}()

/// Repeating timer with tolerance, so macOS can coalesce wakeups (lower CPU / energy use)
@discardableResult
func every(_ interval: TimeInterval, tolerance: TimeInterval, _ block: @escaping () -> Void) -> Timer {
    let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in block() }
    t.tolerance = tolerance
    return t
}

