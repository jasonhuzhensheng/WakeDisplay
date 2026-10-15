// Product extras: What's New after an update, Report an Issue, crash reporting, sponsorship.
// 产品化功能：更新后的「新功能」窗口、反馈问题、崩溃上报、赞助入口。
import Cocoa

private let ud = UserDefaults.standard
let repoURL = "https://github.com/jasonhuzhensheng/WakeDisplay"

// MARK: - Sponsorship (fill in to show; empty entries are hidden from the menu)

enum Sponsor {
    static let githubSponsors = "https://github.com/sponsors/jasonhuzhensheng"
    /// (label, address). Leave the address empty to hide that coin.
    static let crypto: [(String, String)] = [
        ("BTC", ""),
        ("ETH / USDT (ERC-20)", ""),
        ("SOL", ""),
    ]
    static var cryptoVisible: [(String, String)] { crypto.filter { !$0.1.isEmpty } }
}

// MARK: - What's New (shown once after the version changes)

enum WhatsNew {
    /// Call at launch. If the app was updated since the last run, show that release's notes.
    static func showIfUpdated() {
        let cur = Updater.currentVersion
        let last = ud.string(forKey: "lastRunVersion")
        ud.set(cur, forKey: "lastRunVersion")
        guard let last, last != cur, Updater.isNewer(cur, than: last) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { show(cur) }
    }

    /// Fetch the GitHub release notes for a version and show the "What's new" section
    static func show(_ version: String = Updater.currentVersion) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/jasonhuzhensheng/WakeDisplay/releases/tags/v\(version)")!)
        req.setValue("WakeDisplay/\(version)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var notes = ""
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let body = json["body"] as? String {
                notes = extract(body)
            }
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = L("What's New in ") + "WakeDisplay v\(version)"
                a.informativeText = notes.isEmpty ? repoURL + "/releases" : notes
                a.addButton(withTitle: L("Close"))
                a.addButton(withTitle: L("Open GitHub"))
                NSApp.activate(ignoringOtherApps: true)
                if a.runModal() == .alertSecondButtonReturn { openURL(repoURL + "/releases/tag/v\(version)") }
            }
        }.resume()
    }

    /// Take the "## What's new" section of the release body and make it plain text
    static func extract(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.lowercased().hasPrefix("## what's new") }) else { return "" }
        var out: [String] = []
        for l in lines[(start + 1)...] {
            if l.hasPrefix("## ") { break }
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            out.append(t.hasPrefix("- ") ? "• " + String(t.dropFirst(2)) : t)
        }
        return out.prefix(20).joined(separator: "\n")
    }
}

// MARK: - Report an Issue (GitHub issue pre-filled with system + display info)

enum Feedback {
    static func systemInfo() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var lines = [
            "- WakeDisplay: v\(Updater.currentVersion)",
            "- macOS: \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            "- Chip: \(Telemetry.architecture)",
            "- Language: \(effectiveLang().rawValue)",
        ]
        for d in physicalExternals() {
            let m = CGDisplayCopyDisplayMode(d)
            let res = m.map { "\($0.width)×\($0.height) (\($0.pixelWidth)×\($0.pixelHeight) px) @ \(Int($0.refreshRate.rounded()))Hz" } ?? "?"
            lines.append("- Display: \(displayName(d)) — \(res)")
        }
        return lines.joined(separator: "\n")
    }

    static func openIssue() {
        let body = """
        **What happened? / 发生了什么？**


        **Steps to reproduce / 复现步骤**
        1.

        **System / 系统信息**
        \(systemInfo())
        """
        var c = URLComponents(string: repoURL + "/issues/new")!
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        if let u = c.url { openURL(u.absoluteString) }
        Telemetry.feature("reportIssue")
    }
}

// MARK: - Crash reporting (anonymous, via TelemetryDeck)
//
// A "running" flag is set at launch and cleared on a clean quit. If it is still set at the next
// launch, the previous run ended abnormally (crash or force quit) → one App.abnormalExit signal.
// Uncaught Objective-C exceptions also record their name/reason for that signal.

enum CrashReporter {
    static var enabled: Bool {
        get { ud.object(forKey: "crashReports") as? Bool ?? true }
        set { ud.set(newValue, forKey: "crashReports") }
    }

    static func start() {
        if ud.bool(forKey: "runningFlag") {
            let reason = ud.string(forKey: "lastExceptionReason") ?? "unknown"
            let ver = ud.string(forKey: "runningVersion") ?? "?"
            if enabled {
                Telemetry.sendAlways("App.abnormalExit", ["Crash.version": ver, "Crash.reason": String(reason.prefix(200))])
            }
        }
        ud.removeObject(forKey: "lastExceptionReason")
        ud.set(true, forKey: "runningFlag")
        ud.set(Updater.currentVersion, forKey: "runningVersion")
        NSSetUncaughtExceptionHandler { e in
            UserDefaults.standard.set("\(e.name.rawValue): \(e.reason ?? "")", forKey: "lastExceptionReason")
            UserDefaults.standard.synchronize()
        }
    }

    static func cleanExit() { ud.set(false, forKey: "runningFlag") }
}

// MARK: - Menus

final class ExtrasMenu: NSObject {
    static let shared = ExtrasMenu()

    private func it(_ title: String, _ sel: Selector?, on: Bool = false, obj: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self
        i.state = on ? .on : .off; i.representedObject = obj
        return i
    }
    private func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let s = NSMenu(); items.forEach { s.addItem($0) }
        let p = NSMenuItem(title: title, action: nil, keyEquivalent: ""); p.submenu = s
        return p
    }

    /// About ▸ Sponsor ▸ (Crypto ▸)
    func sponsorMenu() -> NSMenuItem {
        var items = [it("GitHub Sponsors", #selector(openSponsors))]
        let coins = Sponsor.cryptoVisible
        if !coins.isEmpty {
            items.append(sub(L("Crypto"), coins.map { it($0.0 + "  " + short($0.1), #selector(copyAddress(_:)), obj: $0) }))
        }
        return sub("❤️ " + L("Sponsor"), items)
    }

    /// About ▸ Privacy ▸
    func privacyMenu() -> NSMenuItem {
        sub("🔒 " + L("Privacy"), [
            it(L("Send Anonymous Usage Stats"), #selector(toggleStats), on: Telemetry.enabled),
            it(L("Send Crash Reports"), #selector(toggleCrash), on: CrashReporter.enabled),
        ])
    }

    func whatsNewItem() -> NSMenuItem { it(L("What's New…"), #selector(whatsNew)) }
    func reportIssueItem() -> NSMenuItem { it(L("Report an Issue…"), #selector(reportIssue)) }

    private func short(_ a: String) -> String { a.count > 14 ? "\(a.prefix(6))…\(a.suffix(6))" : a }

    @objc func openSponsors() { openURL(Sponsor.githubSponsors); Telemetry.feature("sponsor") }
    @objc func copyAddress(_ s: NSMenuItem) {
        guard let pair = s.representedObject as? (String, String) else { return }
        let (coin, addr) = pair
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addr, forType: .string)
        let a = NSAlert(); a.messageText = L("Address copied to clipboard."); a.informativeText = "\(coin)\n\(addr)"
        NSApp.activate(ignoringOtherApps: true); a.runModal()
        Telemetry.feature("sponsorCrypto")
    }
    @objc func toggleStats() { Telemetry.enabled.toggle() }
    @objc func toggleCrash() { CrashReporter.enabled.toggle() }
    @objc func whatsNew() { WhatsNew.show() }
    @objc func reportIssue() { Feedback.openIssue() }
}
