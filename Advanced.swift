// Advanced display features (menu → ⚙️ Advanced):
//   brightness / volume / input source over DDC, extra dimming below minimum, refresh-rate switch,
//   soft-disconnect a display, layout presets, and remembering settings per display.
// 高级显示器功能：DDC 亮度 / 音量 / 输入源、低于最低亮度的额外调暗、刷新率切换、软断开显示器、布局预设、按显示器记住设置。
import Cocoa
import Carbon

/// Stable per-monitor key (vendor-model-serial), independent of the session's display ID
func monitorKey(_ d: CGDirectDisplayID) -> String {
    "\(CGDisplayVendorNumber(d))-\(CGDisplayModelNumber(d))-\(CGDisplaySerialNumber(d))"
}
private let ud = UserDefaults.standard

// MARK: - DDC: brightness, volume, mute, input (applies to all external monitors)

enum DDC {
    static var brightness: Int { ud.object(forKey: "ddcBrightness") as? Int ?? 50 }
    static var volume: Int { ud.object(forKey: "ddcVolume") as? Int ?? 50 }

    private static func write(_ vcp: UInt8, _ value: Int) {
        DispatchQueue.global(qos: .userInitiated).async { ddcWrite(vcp: vcp, value: UInt16(max(0, min(65535, value)))) }
    }
    static func setBrightness(_ v: Int) {
        let c = max(0, min(100, v))
        ud.set(c, forKey: "ddcBrightness")
        for d in physicalExternals() { ud.set(c, forKey: "bright.\(monitorKey(d))") }   // remembered per monitor
        write(0x10, c)
    }
    static func step(_ delta: Int) { setBrightness(brightness + delta) }
    static func setVolume(_ v: Int) {
        let c = max(0, min(100, v)); ud.set(c, forKey: "ddcVolume"); write(0x62, c)
    }
    static func mute(_ on: Bool) { write(0x8D, on ? 1 : 2) }
    static func setInput(_ code: Int) { write(0x60, code) }

    /// Common MCCS input codes; monitors vary, USB-C is often 0x1B but some use DP codes
    static let inputs: [(String, Int)] = [("USB-C", 0x1B), ("DisplayPort 1", 0x0F), ("DisplayPort 2", 0x10),
                                          ("HDMI 1", 0x11), ("HDMI 2", 0x12)]
}

// MARK: - Extra dimming (black overlay on external screens, below the panel's minimum)

enum Dimmer {
    private static var windows: [NSWindow] = []
    static var level: Double {
        get { ud.object(forKey: "dimLevel") as? Double ?? 0 }
        set { ud.set(newValue, forKey: "dimLevel"); apply() }
    }

    static func apply() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard level > 0 else { return }
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  CGDisplayIsBuiltin(id) == 0, !isVirtual(id) else { continue }
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = NSColor.black.withAlphaComponent(level)
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}

// MARK: - Soft disconnect (private CoreGraphics call, same one display utilities use)

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

enum SoftDisconnect {
    /// IDs we disabled; persisted so a crash never leaves a monitor stuck off
    static var disabled: [CGDirectDisplayID] {
        get { (ud.array(forKey: "softDisabled") as? [Int] ?? []).map { CGDirectDisplayID($0) } }
        set { ud.set(newValue.map { Int($0) }, forKey: "softDisabled") }
    }
    static func set(_ d: CGDirectDisplayID, enabled: Bool) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        _ = CGSConfigureDisplayEnabled(cfg, d, enabled)
        CGCompleteDisplayConfiguration(cfg, .forSession)
    }
    static func disconnect(_ d: CGDirectDisplayID) {
        // Never switch off the last visible screen
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        guard Int(n) > 1 else { NSSound.beep(); return }
        set(d, enabled: false)
        disabled = Array(Set(disabled + [d]))
    }
    static func reconnectAll() {
        for d in disabled { set(d, enabled: true) }
        disabled = []
    }
}

// MARK: - Refresh rate

func refreshModes(_ d: CGDirectDisplayID) -> [CGDisplayMode] {
    guard let cur = CGDisplayCopyDisplayMode(d) else { return [] }
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let all = (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] ?? []).filter {
        $0.width == cur.width && $0.height == cur.height && $0.pixelWidth == cur.pixelWidth && $0.refreshRate > 0
    }
    var seen = Set<Int>(), out: [CGDisplayMode] = []
    for m in all.sorted(by: { $0.refreshRate > $1.refreshRate }) where seen.insert(Int(m.refreshRate.rounded())).inserted {
        out.append(m)
    }
    return out
}

// MARK: - Layout presets (display positions, by monitor)

enum Layouts {
    static func has(_ slot: Int) -> Bool { ud.dictionary(forKey: "layout\(slot)") != nil }
    static func save(_ slot: Int) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        var dict: [String: [Double]] = [:]
        for d in ids.prefix(Int(n)) where !isVirtual(d) {
            let b = CGDisplayBounds(d)
            dict[monitorKey(d)] = [Double(b.origin.x), Double(b.origin.y)]
        }
        ud.set(dict, forKey: "layout\(slot)")
    }
    static func apply(_ slot: Int) {
        guard let dict = ud.dictionary(forKey: "layout\(slot)") as? [String: [Double]] else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        for d in ids.prefix(Int(n)) {
            if let o = dict[monitorKey(d)], o.count == 2 {
                CGConfigureDisplayOrigin(cfg, d, Int32(o[0]), Int32(o[1]))
            }
        }
        CGCompleteDisplayConfiguration(cfg, .permanently)
    }
}

// MARK: - Remember settings per display (scaling mode + DDC brightness), re-applied on connect

enum PerDisplay {
    static var enabled: Bool {
        get { ud.object(forKey: "rememberPerDisplay") as? Bool ?? true }
        set { ud.set(newValue, forKey: "rememberPerDisplay") }
    }
    /// Called after the user picks a scaling mode for a physical display
    static func saveMode(_ d: CGDirectDisplayID) {
        guard hidpiVirtuals[d] == nil, let m = CGDisplayCopyDisplayMode(d) else { return }
        ud.set([m.width, m.height, m.pixelWidth, Int(m.refreshRate.rounded())], forKey: "mode.\(monitorKey(d))")
    }
    static func restore(_ d: CGDirectDisplayID) {
        guard enabled else { return }
        let key = monitorKey(d)
        if hidpiVirtuals[d] == nil, let s = ud.array(forKey: "mode.\(key)") as? [Int], s.count == 4 {
            let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let all = CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] ?? []
            if let m = all.first(where: { $0.width == s[0] && $0.height == s[1] && $0.pixelWidth == s[2] && Int($0.refreshRate.rounded()) == s[3] })
                ?? all.first(where: { $0.width == s[0] && $0.height == s[1] && $0.pixelWidth == s[2] }) {
                setMode(d, m)
            }
        }
        if let b = ud.object(forKey: "bright.\(key)") as? Int {
            DispatchQueue.global().async { ddcWrite(vcp: 0x10, value: UInt16(b)) }
        }
    }
    static func restoreAll() {
        for d in physicalExternals() { restore(d) }
        restoreSharpScaling()
        Dimmer.apply()
    }
}

/// Re-apply per-display settings when a monitor is plugged in (debounced)
private var reconfigPending = false
func startDisplayWatcher() {
    CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
        guard flags.contains(.addFlag) || flags.contains(.removeFlag) else { return }
        DispatchQueue.main.async {
            guard !reconfigPending else { return }
            reconfigPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                reconfigPending = false
                PerDisplay.restoreAll()
            }
        }
    }, nil)
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in Dimmer.apply() }
}

// MARK: - Menu

final class AdvancedMenu: NSObject {
    static let shared = AdvancedMenu()

    private func it(_ title: String, _ sel: Selector?, on: Bool = false, obj: Any? = nil, enabled: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self; i.state = on ? .on : .off; i.representedObject = obj; i.isEnabled = enabled
        return i
    }
    private func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let s = NSMenu(); s.autoenablesItems = false; items.forEach { s.addItem($0) }
        let p = NSMenuItem(title: title, action: nil, keyEquivalent: ""); p.submenu = s
        return p
    }

    func build(extra: [NSMenuItem] = []) -> NSMenuItem {
        var items: [NSMenuItem] = [AutoOutdoor.menuItem(), .separator()]
        let exts = physicalExternals()

        // Brightness
        var b: [NSMenuItem] = [it(L("Brightness Up  ⌃⌥⌘↑"), #selector(brightUp)), it(L("Brightness Down  ⌃⌥⌘↓"), #selector(brightDown)), .separator()]
        for v in [0, 25, 50, 75, 100] { b.append(it("\(v)%", #selector(setBright(_:)), on: DDC.brightness == v, obj: v)) }
        items.append(sub("☀︎ " + L("Brightness (External)"), b))

        // Volume
        var vol: [NSMenuItem] = []
        for v in [0, 25, 50, 75, 100] { vol.append(it("\(v)%", #selector(setVol(_:)), on: DDC.volume == v, obj: v)) }
        vol += [.separator(), it(L("Mute"), #selector(mute(_:)), obj: true), it(L("Unmute"), #selector(mute(_:)), obj: false)]
        items.append(sub("🔊 " + L("Volume (External)"), vol))

        // Extra dimming
        var dim: [NSMenuItem] = [it(L("Off"), #selector(setDim(_:)), on: Dimmer.level == 0, obj: 0.0)]
        for v in [0.25, 0.5, 0.75] { dim.append(it("\(Int(v * 100))%", #selector(setDim(_:)), on: abs(Dimmer.level - v) < 0.01, obj: v)) }
        items.append(sub("🌙 " + L("Extra Dimming"), dim))

        // Input source
        items.append(sub("🔌 " + L("Input Source"), DDC.inputs.map { it($0.0, #selector(setInput(_:)), obj: $0.1) }))

        items.append(.separator())

        // Refresh rate, per display
        for d in exts {
            let cur = CGDisplayCopyDisplayMode(d).map { Int($0.refreshRate.rounded()) } ?? 0
            let rr = refreshModes(d).map { m -> NSMenuItem in
                let hz = Int(m.refreshRate.rounded())
                return it("\(hz) Hz", #selector(setRefresh(_:)), on: hz == cur, obj: [d, m] as [Any])
            }
            items.append(sub("⏱ " + L("Refresh Rate — ") + displayName(d), rr.isEmpty ? [it("—", nil, enabled: false)] : rr))
        }

        // Soft disconnect
        var dis: [NSMenuItem] = exts.map { it(displayName($0), #selector(disconnect(_:)), obj: $0) }
        if !dis.isEmpty { dis.append(.separator()) }
        dis.append(it(L("Reconnect All Displays"), #selector(reconnect), enabled: !SoftDisconnect.disabled.isEmpty))
        items.append(sub("👁 " + L("Disconnect Display"), dis))

        // Layout presets
        var lay: [NSMenuItem] = []
        for s in 1...3 { lay.append(it(L("Apply Preset ") + "\(s)" + (Layouts.has(s) ? "" : "  " + L("(empty)")), #selector(applyLayout(_:)), obj: s, enabled: Layouts.has(s))) }
        lay.append(.separator())
        for s in 1...3 { lay.append(it(L("Save Current Layout as Preset ") + "\(s)", #selector(saveLayout(_:)), obj: s)) }
        items.append(sub("🗂 " + L("Layout Presets"), lay))

        items.append(.separator())
        items.append(it(L("Remember Settings per Display"), #selector(toggleRemember), on: PerDisplay.enabled))
        if !extra.isEmpty { items.append(.separator()); items += extra }

        return sub("⚙️ " + L("Advanced"), items)
    }

    @objc func brightUp() { DDC.step(10); Telemetry.feature("brightness") }
    @objc func brightDown() { DDC.step(-10); Telemetry.feature("brightness") }
    @objc func setBright(_ s: NSMenuItem) { if let v = s.representedObject as? Int { DDC.setBrightness(v); Telemetry.feature("brightness") } }
    @objc func setVol(_ s: NSMenuItem) { if let v = s.representedObject as? Int { DDC.setVolume(v); Telemetry.feature("volume") } }
    @objc func mute(_ s: NSMenuItem) { if let on = s.representedObject as? Bool { DDC.mute(on); Telemetry.feature("volume") } }
    @objc func setDim(_ s: NSMenuItem) { if let v = s.representedObject as? Double { Dimmer.level = v; if v > 0 { Telemetry.feature("extraDimming") } } }
    @objc func setInput(_ s: NSMenuItem) { if let v = s.representedObject as? Int { DDC.setInput(v); Telemetry.feature("inputSource") } }
    @objc func setRefresh(_ s: NSMenuItem) {
        guard let a = s.representedObject as? [Any], a.count == 2, let d = a[0] as? CGDirectDisplayID else { return }
        setMode(d, a[1] as! CGDisplayMode)
        PerDisplay.saveMode(d)
        Telemetry.feature("refreshRate")
    }
    @objc func disconnect(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { SoftDisconnect.disconnect(d); Telemetry.feature("softDisconnect") } }
    @objc func reconnect() { SoftDisconnect.reconnectAll() }
    @objc func saveLayout(_ s: NSMenuItem) { if let n = s.representedObject as? Int { Layouts.save(n); Telemetry.feature("layoutPreset") } }
    @objc func applyLayout(_ s: NSMenuItem) { if let n = s.representedObject as? Int { Layouts.apply(n) } }
    @objc func toggleRemember() { PerDisplay.enabled.toggle() }
}
