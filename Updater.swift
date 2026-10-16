// Copyright (c) 2026 Jason Hu (胡震生) — MIT License. The WakeDisplay name and logo are not covered, see TRADEMARKS.md
// Self-updater: checks GitHub Releases, downloads the zip, verifies it and swaps the app in place.
// No Sparkle / no server: releases are already built and published by GitHub Actions.
// 自动更新：查询 GitHub Releases，下载 zip，校验后原地替换 App 并重启。
import Cocoa

enum Updater {
    static let latestAPI = URL(string: "https://api.github.com/repos/jasonhuzhensheng/WakeDisplay/releases/latest")!
    static let bundleID = "com.jason.wakedisplay"
    private static var busy = false

    /// On by default
    static var autoUpdate: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdate") }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// "1.10.1" > "1.9" — numeric, component by component
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    struct Release { let version: String; let zipURL: URL; let page: URL? }

    static func fetchLatest(_ done: @escaping (Release?) -> Void) {
        var req = URLRequest(url: latestAPI)
        req.setValue("WakeDisplay/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        net.dataTask(with: req) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, tag.hasPrefix("v"),
                  let assets = json["assets"] as? [[String: Any]],
                  let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let urlStr = zip["browser_download_url"] as? String, let url = URL(string: urlStr),
                  url.host == "github.com"
            else { DispatchQueue.main.async { done(nil) }; return }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            let r = Release(version: String(tag.dropFirst()), zipURL: url, page: page)
            DispatchQueue.main.async { done(r) }
        }.resume()
    }

    /// Background schedule: 1 min after launch, then every 6 hours. Installs silently when auto-update is on.
    static func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { backgroundCheck() }
    }

    /// Called from the app's hourly tick; checks at most every 6 hours
    private static var lastCheck = Date()
    static func hourlyTick() {
        guard Date().timeIntervalSince(lastCheck) >= 6 * 3600 - 600 else { return }
        backgroundCheck()
    }

    private static func backgroundCheck() {
        lastCheck = Date()
        guard autoUpdate, !busy, !outdoor.isOn else { return }   // don't yank the screen out from under outdoor mode
        fetchLatest { r in
            guard let r, isNewer(r.version, than: currentVersion) else { return }
            install(r, interactive: false)
        }
    }

    /// Menu → Check for Updates…
    static func checkInteractively() {
        fetchLatest { r in
            guard let r else { alert(L("Update failed: ") + "GitHub", ""); return }
            guard isNewer(r.version, than: currentVersion) else {
                alert(L("You're up to date."), "WakeDisplay \(currentVersion)"); return
            }
            let a = NSAlert()
            a.messageText = L("A new version is available: ") + "v\(r.version)"
            a.informativeText = "v\(currentVersion) → v\(r.version)"
            a.addButton(withTitle: L("Install and Relaunch"))
            a.addButton(withTitle: L("Later"))
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn { install(r, interactive: true) }
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }

    /// Download → unzip → verify bundle id + version → replace in place → relaunch
    static func install(_ r: Release, interactive: Bool) {
        guard !busy else { return }
        busy = true
        let fail: (String) -> Void = { msg in
            DispatchQueue.main.async { busy = false; if interactive { alert(L("Update failed: ") + msg, "") } }
        }
        net.downloadTask(with: r.zipURL) { tmp, _, err in
            guard let tmp else { fail(err?.localizedDescription ?? "download"); return }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("WakeDisplayUpdate-\(UUID().uuidString)")
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("update.zip")
                try fm.moveItem(at: tmp, to: zip)
                let unzip = Process()
                unzip.launchPath = "/usr/bin/ditto"
                unzip.arguments = ["-x", "-k", zip.path, work.path]
                try unzip.run(); unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else { fail("unzip"); return }

                let newApp = work.appendingPathComponent("WakeDisplay.app")
                guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
                      info["CFBundleIdentifier"] as? String == bundleID,
                      info["CFBundleShortVersionString"] as? String == r.version
                else { fail("verify"); return }

                let target = Bundle.main.bundleURL
                _ = try fm.replaceItemAt(target, withItemAt: newApp)
                // Re-register the URL scheme for the new bundle
                let reg = Process()
                reg.launchPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                reg.arguments = ["-f", target.path]
                try? reg.run(); reg.waitUntilExit()
                Telemetry.send("App.updated", ["Update.from": currentVersion, "Update.to": r.version])
                // Start the NEW instance first, then quit this one. (A child "sleep; open" script gets
                // killed together with us when launchd started the app at login, so never rely on it.)
                DispatchQueue.main.async {
                    CrashReporter.cleanExit()   // the new instance must not report this as a crash
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.createsNewApplicationInstance = true
                    cfg.activates = false
                    NSWorkspace.shared.openApplication(at: target, configuration: cfg) { _, err in
                        DispatchQueue.main.async {
                            if let err { busy = false; if interactive { alert(L("Update failed: ") + err.localizedDescription, "") }; return }
                            NSApp.terminate(nil)
                        }
                    }
                }
            } catch {
                fail(error.localizedDescription)
            }
        }.resume()
    }
}
