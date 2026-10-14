// WakeDisplay — macOS menu-bar utility: wake dark USB-C external displays / unlock hidden HiDPI scaling
// WakeDisplay — macOS 菜单栏小工具：唤醒黑屏的 USB-C 外接显示器 / 解锁隐藏 HiDPI 缩放
// Author: 胡震生 Jason Hu (@HUZHENSHENG · 0xBig2)  ·  MIT License
// https://github.com/jasonhuzhensheng/WakeDisplay
// Build: see build.sh (Xcode Command Line Tools only)
import Cocoa
import Carbon
import IOKit
import IOKit.pwr_mgt

// MARK: - Localization (English by default, Chinese selectable / 默认英文，可切换中文)

enum Lang: String { case en, zh }
var currentLang: Lang = Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "en") ?? .en

/// L("English text") → text in the current language; falls back to English
func L(_ en: String) -> String { currentLang == .zh ? (zhTable[en] ?? en) : en }

let hidpiHelpEN = """
macOS only generates HiDPI scaling modes for displays with high enough pixel density (usually ≥ 4K).
1080p / 2K portable monitors typically expose native modes only, so System Settings offers no "Larger Text" either.

Options:
• Pick a lower non-HiDPI resolution here (e.g. 1600×900): bigger text, slightly soft.
• For "big and sharp" you need a virtual HiDPI display mirrored onto the physical one (BetterDisplay's approach); this may be added to WakeDisplay later.
"""
let hidpiHelpZH = """
macOS 只对像素密度足够高的显示器（通常 ≥ 4K）自动提供 HiDPI 缩放模式。
1080p / 2K 便携屏一般只有原生模式，所以系统设置里也没有「更大文本」。

可选方案：
• 先在本菜单里选一个较低的非 HiDPI 分辨率（如 1600×900），字体会变大但略模糊；
• 要「既大又清晰」，需要创建一块虚拟 HiDPI 屏再镜像到物理屏（BetterDisplay 的做法），本工具后续可加入该功能。
"""
let aboutEN = """
macOS menu-bar utility: wake dark USB-C external displays with one click and unlock the HiDPI scaling modes macOS hides.

Author: Jason Hu 胡震生 (大老二)
X: @HUZHENSHENG  ·  0xBig2

Built with: Claude Fable 5.1 (Anthropic)
License: MIT
"""
let aboutZH = """
macOS 菜单栏小工具：一键唤醒黑屏的 USB-C 外接显示器，解锁系统隐藏的 HiDPI 缩放模式。

作者：大老二 胡震生（Jason Hu）
X：@HUZHENSHENG  ·  0xBig2

开发工具：Claude Fable 5.1（Anthropic）
开源协议：MIT
"""
let pmsetMsgEN = "Will run:\nsudo pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0\n\nEffect: USB-C power is no longer cut when the lid is closed or the screen is locked. A laptop on battery will drain faster. Continue?"
let pmsetMsgZH = "将执行：\nsudo pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0\n\n效果：合盖/锁屏时不再切断 USB-C 供电。笔记本用电池时会更耗电。继续？"
let edidMsgEN = "Will delete /Library/Preferences/com.apple.windowserver.displays.plist and the user-level display config, then restart the Mac.\nPersonal data is untouched, but display arrangement / scaling settings will reset. Continue?"
let edidMsgZH = "将删除 /Library/Preferences/com.apple.windowserver.displays.plist 及用户级显示配置，然后重启 Mac。\n不影响个人数据，但显示器排列/缩放设置会重置。继续？"

let zhTable: [String: String] = [
    "Wake Display    ⌘⇧R": "唤醒显示器    ⌘⇧R",
    "Force Reset (sleep → re-handshake)": "强制重置（关屏 → 重新握手）",
    "Prevent Display Sleep": "阻止显示器休眠",
    "Auto-Wake (external asleep while Mac in use)": "自动唤醒（外屏休眠而电脑在用时自动点亮）",
    "Scaling / Text Size — ": "缩放 / 字体大小 — ",
    "Larger Text  ⌘⇧+": "更大文本  ⌘⇧+",
    "Smaller Text  ⌘⇧−": "更小文本  ⌘⇧−",
    "  HiDPI (sharp)": "  HiDPI（清晰）",
    "⚠️ No HiDPI modes for this display (help)": "⚠️ 此显示器没有可用的 HiDPI 模式（见帮助）",
    "Display ": "显示器 ",
    "Apply Anti-Disconnect Power Policy (sudo pmset)": "写入防断连电源策略（sudo pmset）",
    "Restore Default Power Policy": "恢复系统默认电源策略",
    "Show Current Power Settings": "查看当前电源参数",
    "Reset Display Cache (EDID) & Restart…": "清除显示器缓存（EDID）并重启…",
    "Language": "语言 / Language",
    "Launch at Login": "开机自动启动",
    "About WakeDisplay…": "关于 WakeDisplay…",
    "Quit": "退出",
    "Continue": "继续", "Cancel": "取消", "Close": "关闭",
    "Done": "已写入", "Failed": "失败", "Restored defaults": "已恢复默认",
    "Apply power policy": "写入电源策略",
    "Restore defaults": "恢复默认",
    "Will run sudo pmset restoredefaults. Continue?": "将执行 sudo pmset restoredefaults，继续？",
    "Reset display cache": "清除显示器缓存",
    "No HiDPI modes — what now?": "没有 HiDPI 模式怎么办",
    "Open GitHub": "打开 GitHub",
    "Follow on X @HUZHENSHENG": "关注 X @HUZHENSHENG",
    hidpiHelpEN: hidpiHelpZH,
    aboutEN: aboutZH,
    pmsetMsgEN: pmsetMsgZH,
    edidMsgEN: edidMsgZH,
]

// MARK: - Core: wake logic

/// Equivalent to Option-click "Detect Displays": ask every display controller to re-probe / re-handshake
func probeDisplays() {
    let classes = ["IODisplayConnect", "AppleCLCD2", "IOMobileFramebuffer", "AppleDisplay", "DCPAVControllerProxy"]
    for cls in classes {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, IOServiceMatching(cls), &iter) == KERN_SUCCESS else { continue }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            IOServiceRequestProbe(svc, 0)
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
    }
}

/// Declare user activity to power management; forces all screens on (≈ caffeinate -u)
func declareUserActivity() {
    var id: IOPMAssertionID = 0
    IOPMAssertionDeclareUserActivity("WakeDisplay wake" as CFString, kIOPMUserActiveLocal, &id)
}

@discardableResult
func shell(_ cmd: String) -> String {
    let p = Process()
    p.launchPath = "/bin/zsh"
    p.arguments = ["-c", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try? p.run()
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

/// Commands needing admin rights: shows the system password prompt
func sudoShell(_ cmd: String) -> (ok: Bool, out: String) {
    let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let src = "do shell script \"\(escaped)\" with administrator privileges"
    var err: NSDictionary?
    let res = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err = err { return (false, "\(err[NSAppleScript.errorMessage] ?? err)") }
    return (true, res?.stringValue ?? "")
}

// MARK: - Method 2: mirror toggle, forces a fresh DP link (public CoreGraphics API)
func externalDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).filter { CGDisplayIsBuiltin($0) == 0 }
}
func mirrorToggle() {
    let main = CGMainDisplayID()
    let exts = externalDisplays().filter { $0 != main }
    guard !exts.isEmpty else { return }
    var cfg: CGDisplayConfigRef?
    if CGBeginDisplayConfiguration(&cfg) == .success {
        for d in exts { CGConfigureDisplayMirrorOfDisplay(cfg, d, main) }
        CGCompleteDisplayConfiguration(cfg, .forSession)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        var cfg2: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&cfg2) == .success {
            for d in exts { CGConfigureDisplayMirrorOfDisplay(cfg2, d, kCGNullDirectDisplay) }
            CGCompleteDisplayConfiguration(cfg2, .forSession)
        }
    }
}

// MARK: - Method 3: DDC/CI power-on command over USB-C/DP I²C (Apple Silicon)
typealias IOAVServiceRef = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ a: CFAllocator?, _ s: io_service_t) -> Unmanaged<IOAVServiceRef>?
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ svc: IOAVServiceRef, _ chip: UInt32, _ addr: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

func ddcWrite(vcp: UInt8, value: UInt16) {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(0, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(iter) }
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        defer { svc = IOIteratorNext(iter) }
        let loc = IORegistryEntryCreateCFProperty(svc, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        guard loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, svc)?.takeRetainedValue() else { IOObjectRelease(svc); continue }
        let hi = UInt8(value >> 8), lo = UInt8(value & 0xFF)
        var data: [UInt8] = [0x84, 0x03, vcp, hi, lo, 0]
        data[5] = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ vcp ^ hi ^ lo
        for _ in 0..<3 {   // retry: a sleeping panel often swallows the first packet
            data.withUnsafeMutableBytes { _ = IOAVServiceWriteI2C(av, 0x37, 0x51, $0.baseAddress!, 6) }
            usleep(50_000)
        }
        IOObjectRelease(svc)
    }
}
func ddcPowerOn() { ddcWrite(vcp: 0xD6, value: 1) }   // VCP D6 = Power Mode, 1 = On

/// Level 1 wake: user activity + DDC power-on + re-probe + mirror toggle
func wakeSoft() {
    declareUserActivity()
    ddcPowerOn()
    probeDisplays()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { mirrorToggle() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { ddcPowerOn(); probeDisplays(); declareUserActivity() }
}

/// Level 2 wake: sleep all displays, then wake, forcing USB-C re-enumeration
func wakeHard() {
    DispatchQueue.global().async {
        shell("pmset displaysleepnow")
        Thread.sleep(forTimeInterval: 3)
        DispatchQueue.main.async { wakeSoft() }
    }
}

// MARK: - Scaling / text size (lists hidden HiDPI modes ≈ System Settings "Larger / Smaller Text")
struct ScaleMode {
    let mode: CGDisplayMode
    var w: Int { mode.width }; var h: Int { mode.height }
    var hidpi: Bool { mode.pixelWidth > mode.width }
    var hz: Int { Int(mode.refreshRate.rounded()) }
    var title: String { "\(w) × \(h)" + (hidpi ? L("  HiDPI (sharp)") : "") + (hz > 0 ? "  \(hz)Hz" : "") }
}
func scaleModes(for d: CGDirectDisplayID) -> [ScaleMode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let all = CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] else { return [] }
    let cur = CGDisplayCopyDisplayMode(d)
    var seen = Set<String>(); var out: [ScaleMode] = []
    for m in all where m.isUsableForDesktopGUI() {
        let key = "\(m.width)x\(m.height)x\(m.pixelWidth > m.width)"
        if seen.contains(key) { continue }
        let best = all.filter { "\($0.width)x\($0.height)x\($0.pixelWidth > $0.width)" == key }
            .sorted { a, b in
                if let c = cur { if a.refreshRate == c.refreshRate { return true }; if b.refreshRate == c.refreshRate { return false } }
                return a.refreshRate > b.refreshRate }.first!
        seen.insert(key); out.append(ScaleMode(mode: best))
    }
    return out.sorted { a, b in a.hidpi != b.hidpi ? a.hidpi : (a.w != b.w ? a.w > b.w : a.h > b.h) }
}
func displayName(_ d: CGDirectDisplayID) -> String {
    for s in NSScreen.screens where (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d { return s.localizedName }
    return L("Display ") + "\(d)"
}
func setMode(_ d: CGDirectDisplayID, _ m: CGDisplayMode) {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
    CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
    CGCompleteDisplayConfiguration(cfg, .permanently)
}
/// Larger text = next lower HiDPI resolution; smaller text = the reverse
func stepText(_ d: CGDirectDisplayID, larger: Bool) {
    let modes = scaleModes(for: d).filter { $0.hidpi }.sorted { $0.w > $1.w }
    guard let cur = CGDisplayCopyDisplayMode(d), !modes.isEmpty else { return }
    let idx = modes.firstIndex { $0.w == cur.width && $0.h == cur.height && $0.hidpi } ?? (larger ? -1 : modes.count)
    let next = larger ? idx + 1 : idx - 1
    guard modes.indices.contains(next) else { return }
    setMode(d, modes[next].mode)
}

// MARK: - Menu-bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var preventSleepID: IOPMAssertionID = 0
    var autoWakeTimer: Timer?
    var hotKeyRefs: [EventHotKeyRef?] = []

    let launchAgent = NSString(string: "~/Library/LaunchAgents/com.jason.wakedisplay.plist").expandingTildeInPath

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "display", accessibilityDescription: "WakeDisplay")
            btn.action = #selector(statusClicked(_:))
            btn.target = self
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        registerHotKeys()
    }

    /// Left-click = wake now; right-click = menu
    @objc func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            wakeSoft()
            flash()
        }
    }

    func flash() {
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        }
    }

    func item(_ title: String, _ sel: Selector?, state: Bool = false, obj: Any? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self; it.state = state ? .on : .off; it.representedObject = obj
        return it
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item("🔆 " + L("Wake Display    ⌘⇧R"), #selector(actWakeSoft)))
        m.addItem(item("🔁 " + L("Force Reset (sleep → re-handshake)"), #selector(actWakeHard)))
        m.addItem(.separator())
        m.addItem(item("☕️ " + L("Prevent Display Sleep"), #selector(actToggleSleep), state: preventSleepID != 0))
        m.addItem(item("🤖 " + L("Auto-Wake (external asleep while Mac in use)"), #selector(actToggleAutoWake), state: autoWakeTimer != nil))
        m.addItem(.separator())
        for d in externalDisplays() {
            let sub = NSMenu()
            sub.addItem(item(L("Larger Text  ⌘⇧+"), #selector(actLarger(_:)), obj: d))
            sub.addItem(item(L("Smaller Text  ⌘⇧−"), #selector(actSmaller(_:)), obj: d))
            sub.addItem(.separator())
            let cur = CGDisplayCopyDisplayMode(d)
            let modes = scaleModes(for: d)
            if !modes.contains(where: { $0.hidpi }) {
                sub.addItem(item(L("⚠️ No HiDPI modes for this display (help)"), #selector(actHiDPIHelp)))
                sub.addItem(.separator())
            }
            for sm in modes {
                let on = cur.map { $0.width == sm.w && $0.height == sm.h && ($0.pixelWidth > $0.width) == sm.hidpi } ?? false
                sub.addItem(item(sm.title, #selector(actSetMode(_:)), state: on, obj: [d, sm.mode] as [Any]))
            }
            let parent = NSMenuItem(title: "🔍 " + L("Scaling / Text Size — ") + displayName(d), action: nil, keyEquivalent: "")
            m.addItem(parent); m.setSubmenu(sub, for: parent)
        }
        m.addItem(.separator())
        m.addItem(item("⚡️ " + L("Apply Anti-Disconnect Power Policy (sudo pmset)"), #selector(actApplyPmset)))
        m.addItem(item("↩️ " + L("Restore Default Power Policy"), #selector(actRestorePmset)))
        m.addItem(item("🔍 " + L("Show Current Power Settings"), #selector(actShowPmset)))
        m.addItem(item("🧹 " + L("Reset Display Cache (EDID) & Restart…"), #selector(actResetEDID)))
        m.addItem(.separator())
        let langSub = NSMenu()
        langSub.addItem(item("English", #selector(actSetLang(_:)), state: currentLang == .en, obj: "en"))
        langSub.addItem(item("中文", #selector(actSetLang(_:)), state: currentLang == .zh, obj: "zh"))
        let langParent = NSMenuItem(title: "🌐 " + L("Language"), action: nil, keyEquivalent: "")
        m.addItem(langParent); m.setSubmenu(langSub, for: langParent)
        m.addItem(item(L("Launch at Login"), #selector(actToggleLogin), state: FileManager.default.fileExists(atPath: launchAgent)))
        m.addItem(item(L("About WakeDisplay…"), #selector(actAbout)))
        m.addItem(NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return m
    }

    // MARK: actions
    @objc func actWakeSoft() { wakeSoft(); flash() }
    @objc func actWakeHard() { wakeHard() }

    @objc func actSetLang(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String, let l = Lang(rawValue: code) else { return }
        currentLang = l
        UserDefaults.standard.set(code, forKey: "lang")   // remembered across launches
    }

    @objc func actLarger(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepText(d, larger: true) } }
    @objc func actSmaller(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepText(d, larger: false) } }
    @objc func actSetMode(_ s: NSMenuItem) {
        guard let arr = s.representedObject as? [Any], let d = arr[0] as? CGDirectDisplayID else { return }
        setMode(d, arr[1] as! CGDisplayMode)
    }
    @objc func actHiDPIHelp() { info(L("No HiDPI modes — what now?"), L(hidpiHelpEN)) }

    /// Every 5 s: built-in awake but an external display asleep → wake
    @objc func actToggleAutoWake() {
        if let t = autoWakeTimer { t.invalidate(); autoWakeTimer = nil; return }
        autoWakeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let exts = externalDisplays()
            let builtinAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
            if builtinAwake && exts.contains(where: { CGDisplayIsAsleep($0) != 0 }) { wakeSoft() }
        }
    }

    @objc func actToggleSleep() {
        if preventSleepID != 0 {
            IOPMAssertionRelease(preventSleepID); preventSleepID = 0
        } else {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "WakeDisplay keep awake" as CFString, &preventSleepID)
        }
        statusItem.button?.image = NSImage(systemSymbolName: preventSleepID != 0 ? "display.and.arrow.down" : "display", accessibilityDescription: nil)
    }

    @objc func actApplyPmset() {
        guard confirm(L("Apply power policy"), L(pmsetMsgEN)) else { return }
        let r = sudoShell("/usr/bin/pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0")
        info(r.ok ? L("Done") : L("Failed"), r.ok ? shell("pmset -g | egrep ' sleep| standby|autopoweroff|powernap'") : r.out)
    }

    @objc func actRestorePmset() {
        guard confirm(L("Restore defaults"), L("Will run sudo pmset restoredefaults. Continue?")) else { return }
        let r = sudoShell("/usr/bin/pmset restoredefaults")
        info(r.ok ? L("Restored defaults") : L("Failed"), r.out)
    }

    @objc func actShowPmset() { info("pmset -g", shell("pmset -g")) }

    @objc func actResetEDID() {
        guard confirm(L("Reset display cache"), L(edidMsgEN)) else { return }
        let r = sudoShell("/bin/rm -f /Library/Preferences/com.apple.windowserver.displays.plist ~/Library/Preferences/ByHost/com.apple.windowserver*.plist; /sbin/shutdown -r now")
        if !r.ok { info(L("Failed"), r.out) }
    }

    @objc func actToggleLogin() {
        if FileManager.default.fileExists(atPath: launchAgent) {
            shell("launchctl unload '\(launchAgent)'"); try? FileManager.default.removeItem(atPath: launchAgent)
        } else {
            let exe = Bundle.main.executablePath ?? ""
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.jason.wakedisplay</string>
              <key>ProgramArguments</key><array><string>\(exe)</string></array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><false/>
            </dict></plist>
            """
            try? FileManager.default.createDirectory(atPath: (launchAgent as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? plist.write(toFile: launchAgent, atomically: true, encoding: .utf8)
            shell("launchctl load '\(launchAgent)'")
        }
    }

    @objc func actAbout() {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let a = NSAlert()
        a.messageText = "WakeDisplay \(ver)"
        a.informativeText = L(aboutEN)
        a.addButton(withTitle: L("Open GitHub"))
        a.addButton(withTitle: L("Follow on X @HUZHENSHENG"))
        a.addButton(withTitle: L("Close"))
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(URL(string: "https://github.com/jasonhuzhensheng/WakeDisplay")!)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(URL(string: "https://x.com/HUZHENSHENG")!)
        default: break
        }
    }

    // MARK: global hotkeys ⌘⇧R / ⌘⇧+ / ⌘⇧−
    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evt, _ in
            var hk = EventHotKeyID()
            GetEventParameter(evt, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            switch hk.id {
            case 1: wakeSoft()
            case 2: if let d = externalDisplays().first { stepText(d, larger: true) }
            case 3: if let d = externalDisplays().first { stepText(d, larger: false) }
            default: break
            }
            return noErr
        }, 1, &spec, nil, nil)
        let keys: [(UInt32, UInt32)] = [(UInt32(kVK_ANSI_R), 1), (UInt32(kVK_ANSI_Equal), 2), (UInt32(kVK_ANSI_Minus), 3)]
        for (code, id) in keys {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(code, UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x57414B45, id: id), GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    // MARK: dialogs
    func confirm(_ t: String, _ msg: String) -> Bool {
        let a = NSAlert(); a.messageText = t; a.informativeText = msg
        a.addButton(withTitle: L("Continue")); a.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }
    func info(_ t: String, _ msg: String) {
        let a = NSAlert(); a.messageText = t; a.informativeText = msg
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
