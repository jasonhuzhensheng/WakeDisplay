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
• For "big and sharp", turn on "Sharp Scaling at Native Resolution" in this submenu: WakeDisplay renders the desktop on a HiDPI virtual display and mirrors your panel onto it, so the panel keeps its native resolution while text gets larger.
"""
let hidpiHelpZH = """
macOS 只对像素密度足够高的显示器（通常 ≥ 4K）自动提供 HiDPI 缩放模式。
1080p / 2K 便携屏一般只有原生模式，所以系统设置里也没有「更大文本」。

可选方案：
• 先在本菜单里选一个较低的非 HiDPI 分辨率（如 1600×900），字体会变大但略模糊；
• 要「既大又清晰」，打开本子菜单里的「原生分辨率清晰缩放」：WakeDisplay 会创建一块虚拟 HiDPI 屏并把物理屏镜像过去，显示器保持原生分辨率，字体变大且清晰。
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
    "Force Reset (sleep → re-handshake, screens blink)": "强制重置（关屏 → 重新握手，屏幕会闪一下）",
    "Prevent Display Sleep": "阻止显示器休眠",
    "Auto-Wake (external asleep while Mac in use)": "自动唤醒（外屏休眠而电脑在用时自动点亮）",
    "Scaling / Text Size — ": "缩放 / 字体大小 — ",
    "Larger Text  ⌘⇧+": "更大文本  ⌘⇧+",
    "Smaller Text  ⌘⇧−": "更小文本  ⌘⇧−",
    "  HiDPI (sharp)": "  HiDPI（清晰）",
    "⚠️ No HiDPI modes for this display (help)": "⚠️ 此显示器没有可用的 HiDPI 模式（见帮助）",
    "Display ": "显示器 ",
    "Sharp Scaling at Native Resolution": "原生分辨率清晰缩放",
    "Looks like ": "看起来像 ",
    "⚠️ No HiDPI modes — turn on Sharp Scaling above (help)": "⚠️ 没有 HiDPI 模式，请打开上面的清晰缩放（帮助）",
    "Could not create the HiDPI virtual display on this Mac.": "无法在这台 Mac 上创建 HiDPI 虚拟显示器。",
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

/// Open a URL in the default browser. NSWorkspace can silently fail from a background (LSUIElement) app
/// right after a modal alert, so fall back to /usr/bin/open.
func openURL(_ s: String) {
    guard let url = URL(string: s) else { return }
    if !NSWorkspace.shared.open(url) {
        let p = Process(); p.launchPath = "/usr/bin/open"; p.arguments = [s]; try? p.run()
    }
}

// MARK: - Method 2: mirror toggle, forces a fresh DP link (public CoreGraphics API)
func externalDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).filter { CGDisplayIsBuiltin($0) == 0 }
}
func mirrorToggle() {
    let main = CGMainDisplayID()
    let exts = physicalExternals().filter { $0 != main && hidpiVirtuals[$0] == nil }
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

/// Level 1 wake (no flicker): user activity + DDC power-on + re-probe
func wakeSoft() {
    declareUserActivity()
    ddcPowerOn()
    probeDisplays()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ddcPowerOn(); probeDisplays(); declareUserActivity() }
}

/// Level 2 wake: sleep all displays, then wake, forcing USB-C re-enumeration
func wakeHard() {
    DispatchQueue.global().async {
        shell("pmset displaysleepnow")
        Thread.sleep(forTimeInterval: 3)
        DispatchQueue.main.async {
            wakeSoft()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { mirrorToggle() }   // screens blink once here
        }
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
    return nameCache[d] ?? L("Display ") + "\(d)"
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

// MARK: - Sharp scaling at native resolution (HiDPI virtual display)
//
// macOS only offers "Larger Text" HiDPI modes for displays it considers dense enough. For others
// (e.g. a 2880×1800 portable screen) we create an invisible HiDPI virtual display, render the
// desktop there at 2× (e.g. "looks like 1920×1200" → 3840×2400 pixels), and mirror the physical
// display onto it. The panel keeps receiving its native 2880×1800 signal, but text is larger
// and still sharp. This is the same technique BetterDisplay uses.

let kVirtualVendor: UInt32 = 0x3141, kVirtualProduct: UInt32 = 0x5744
var hidpiVirtuals: [CGDirectDisplayID: CGVirtualDisplay] = [:]   // physical ID → virtual display
var nameCache: [CGDirectDisplayID: String] = [:]

func isVirtual(_ d: CGDirectDisplayID) -> Bool {
    CGDisplayVendorNumber(d) == kVirtualVendor && CGDisplayModelNumber(d) == kVirtualProduct
}
/// Physical external displays (excludes our own virtual displays)
func physicalExternals() -> [CGDirectDisplayID] { externalDisplays().filter { !isVirtual($0) } }
/// Where scaling changes should be applied: the virtual display if sharp scaling is on, else the display itself
func scalingTarget(_ d: CGDirectDisplayID) -> CGDirectDisplayID { hidpiVirtuals[d]?.displayID ?? d }

func displayKey(_ d: CGDirectDisplayID) -> String {
    "hidpi.\(CGDisplayVendorNumber(d))-\(CGDisplayModelNumber(d))-\(CGDisplaySerialNumber(d))"
}

/// Largest non-HiDPI mode = the panel's native pixel resolution
func nativeMode(_ d: CGDirectDisplayID) -> CGDisplayMode? {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let all = (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
    let cur = CGDisplayCopyDisplayMode(d)
    return all.filter { $0.pixelWidth == $0.width }
        .max { a, b in
            if a.pixelWidth != b.pixelWidth { return a.pixelWidth < b.pixelWidth }
            if let c = cur { return abs(a.refreshRate - c.refreshRate) > abs(b.refreshRate - c.refreshRate) }
            return a.refreshRate < b.refreshRate
        }
}

/// "Looks like" sizes offered for a W×H panel: from 1/2 (largest text) up to native (smallest text)
func logicalSizes(_ W: Int, _ H: Int) -> [(w: Int, h: Int)] {
    let factors: [Double] = [1.0, 0.8889, 0.8, 0.75, 0.6667, 0.5833, 0.5]
    var out: [(Int, Int)] = []
    for f in factors {
        let w = Int((Double(W) * f / 8).rounded()) * 8
        let h = Int((Double(w) * Double(H) / Double(W) / 2).rounded()) * 2
        if !out.contains(where: { $0.0 == w }) { out.append((w, h)) }
    }
    return out.map { (w: $0.0, h: $0.1) }
}

/// Pick the virtual display's HiDPI mode whose logical width is closest to `width`
func virtualMode(_ v: CGDirectDisplayID, width: Int) -> CGDisplayMode? {
    scaleModes(for: v).filter { $0.hidpi }.min { abs($0.w - width) < abs($1.w - width) }?.mode
}

@discardableResult
func enableSharpScaling(_ physical: CGDirectDisplayID, width wanted: Int? = nil) -> Bool {
    if hidpiVirtuals[physical] != nil { return true }
    guard let native = nativeMode(physical) else { return false }
    nameCache[physical] = displayName(physical)
    let W = native.pixelWidth, H = native.pixelHeight
    let hz = native.refreshRate > 0 ? native.refreshRate : 60

    let desc = CGVirtualDisplayDescriptor()
    desc.queue = DispatchQueue.main
    desc.name = "WakeDisplay HiDPI"
    desc.maxPixelsWide = UInt32(W * 2)
    desc.maxPixelsHigh = UInt32(H * 2)
    let mm = CGDisplayScreenSize(physical)
    desc.sizeInMillimeters = mm.width > 0 ? mm : CGSize(width: 340, height: 212)
    desc.vendorID = kVirtualVendor
    desc.productID = kVirtualProduct
    desc.serialNum = physical
    desc.terminationHandler = { _, _ in }

    let vd = CGVirtualDisplay(descriptor: desc)
    let settings = CGVirtualDisplaySettings()
    settings.hiDPI = 1
    // Modes are given in backing pixels (2× the "looks like" size); macOS derives the HiDPI variants
    settings.modes = logicalSizes(W, H).map { CGVirtualDisplayMode(width: $0.w * 2, height: $0.h * 2, refreshRate: CGFloat(hz)) }
    if !vd.apply(settings) {
        settings.modes = logicalSizes(W, H).map { CGVirtualDisplayMode(width: $0.w * 2, height: $0.h * 2, refreshRate: 60) }
        guard vd.apply(settings) else { return false }
    }
    hidpiVirtuals[physical] = vd
    let vid = vd.displayID
    let sizes = logicalSizes(W, H)
    let target = wanted ?? (UserDefaults.standard.object(forKey: displayKey(physical)) as? Int) ?? sizes[min(4, sizes.count - 1)].w   // default ≈ 2/3, e.g. 1920 on a 2880 panel

    // Give WindowServer a moment to bring the virtual display online, then mirror the panel onto it
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        CGConfigureDisplayWithDisplayMode(cfg, physical, native, nil)       // panel stays at native pixels
        if let m = virtualMode(vid, width: target) { CGConfigureDisplayWithDisplayMode(cfg, vid, m, nil) }
        CGConfigureDisplayMirrorOfDisplay(cfg, physical, vid)              // panel shows the HiDPI desktop
        CGCompleteDisplayConfiguration(cfg, .forSession)
    }
    UserDefaults.standard.set(target, forKey: displayKey(physical))
    return true
}

func disableSharpScaling(_ physical: CGDirectDisplayID) {
    guard hidpiVirtuals[physical] != nil else { return }
    var cfg: CGDisplayConfigRef?
    if CGBeginDisplayConfiguration(&cfg) == .success {
        CGConfigureDisplayMirrorOfDisplay(cfg, physical, kCGNullDirectDisplay)
        CGCompleteDisplayConfiguration(cfg, .forSession)
    }
    hidpiVirtuals[physical] = nil          // releasing the object removes the virtual display
    UserDefaults.standard.removeObject(forKey: displayKey(physical))
}

/// Re-enable sharp scaling for displays where it was on last time
func restoreSharpScaling() {
    for d in physicalExternals() where UserDefaults.standard.object(forKey: displayKey(d)) != nil {
        enableSharpScaling(d)
    }
}

/// Larger / smaller text on whatever drives the panel (virtual HiDPI display if sharp scaling is on)
func stepScaled(_ physical: CGDirectDisplayID, larger: Bool) {
    let t = scalingTarget(physical)
    stepText(t, larger: larger)
    if hidpiVirtuals[physical] != nil, let m = CGDisplayCopyDisplayMode(t) {
        UserDefaults.standard.set(m.width, forKey: displayKey(physical))
    }
}

// MARK: - Menu-bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var preventSleepID: IOPMAssertionID = 0
    var autoWakeTimer: Timer?
    var hotKeyRefs: [EventHotKeyRef?] = []

    let launchAgent = NSString(string: "~/Library/LaunchAgents/com.jason.wakedisplay.plist").expandingTildeInPath

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "WakeDisplay")
        // Any click (left or right) opens the menu; contents are rebuilt each time it opens
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        registerHotKeys()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { restoreSharpScaling() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let built = buildMenu()
        let items = built.items
        built.removeAllItems()
        items.forEach { menu.addItem($0) }
    }

    func item(_ title: String, _ sel: Selector?, state: Bool = false, obj: Any? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self; it.state = state ? .on : .off; it.representedObject = obj
        return it
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item("🔆 " + L("Wake Display    ⌘⇧R"), #selector(actWakeSoft)))
        m.addItem(item("🔁 " + L("Force Reset (sleep → re-handshake, screens blink)"), #selector(actWakeHard)))
        m.addItem(.separator())
        m.addItem(item("☕️ " + L("Prevent Display Sleep"), #selector(actToggleSleep), state: preventSleepID != 0))
        m.addItem(item("🤖 " + L("Auto-Wake (external asleep while Mac in use)"), #selector(actToggleAutoWake), state: autoWakeTimer != nil))
        m.addItem(.separator())
        for d in physicalExternals() {
            let sub = NSMenu()
            let sharp = hidpiVirtuals[d] != nil
            let target = scalingTarget(d)
            sub.addItem(item(L("Larger Text  ⌘⇧+"), #selector(actLarger(_:)), obj: d))
            sub.addItem(item(L("Smaller Text  ⌘⇧−"), #selector(actSmaller(_:)), obj: d))
            sub.addItem(.separator())
            var nativeLabel = ""
            if let n = nativeMode(d) { nativeLabel = " (\(n.pixelWidth) × \(n.pixelHeight))" }
            sub.addItem(item("✨ " + L("Sharp Scaling at Native Resolution") + nativeLabel, #selector(actToggleSharp(_:)), state: sharp, obj: d))
            sub.addItem(.separator())
            let cur = CGDisplayCopyDisplayMode(target)
            var modes = scaleModes(for: target)
            if sharp {
                // Only the HiDPI "looks like" modes matter on the virtual display
                modes = modes.filter { $0.hidpi }
            } else if !modes.contains(where: { $0.hidpi }) {
                sub.addItem(item(L("⚠️ No HiDPI modes — turn on Sharp Scaling above (help)"), #selector(actHiDPIHelp)))
                sub.addItem(.separator())
            }
            for sm in modes {
                let on = cur.map { $0.width == sm.w && $0.height == sm.h && ($0.pixelWidth > $0.width) == sm.hidpi } ?? false
                let title = sharp ? L("Looks like ") + "\(sm.w) × \(sm.h)" : sm.title
                sub.addItem(item(title, #selector(actSetMode(_:)), state: on, obj: [d, sm.mode] as [Any]))
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
    @objc func actWakeSoft() { wakeSoft() }
    @objc func actWakeHard() { wakeHard() }

    @objc func actSetLang(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String, let l = Lang(rawValue: code) else { return }
        currentLang = l
        UserDefaults.standard.set(code, forKey: "lang")   // remembered across launches
    }

    @objc func actLarger(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepScaled(d, larger: true) } }
    @objc func actSmaller(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepScaled(d, larger: false) } }
    @objc func actSetMode(_ s: NSMenuItem) {
        guard let arr = s.representedObject as? [Any], let d = arr[0] as? CGDirectDisplayID, let m = arr[1] as? CGDisplayMode else { return }
        setMode(scalingTarget(d), m)
        if hidpiVirtuals[d] != nil { UserDefaults.standard.set(m.width, forKey: displayKey(d)) }
    }
    @objc func actToggleSharp(_ s: NSMenuItem) {
        guard let d = s.representedObject as? CGDirectDisplayID else { return }
        if hidpiVirtuals[d] != nil { disableSharpScaling(d) }
        else if !enableSharpScaling(d) { info(L("Failed"), L("Could not create the HiDPI virtual display on this Mac.")) }
    }
    @objc func actHiDPIHelp() { info(L("No HiDPI modes — what now?"), L(hidpiHelpEN)) }

    /// Every 5 s: built-in awake but an external display asleep → wake
    @objc func actToggleAutoWake() {
        if let t = autoWakeTimer { t.invalidate(); autoWakeTimer = nil; return }
        autoWakeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let exts = physicalExternals()
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
        let resp = a.runModal()
        a.window.orderOut(nil)
        // Open after the modal session has fully ended; fall back to /usr/bin/open if NSWorkspace refuses
        let target: String? = resp == .alertFirstButtonReturn ? "https://github.com/jasonhuzhensheng/WakeDisplay"
                            : resp == .alertSecondButtonReturn ? "https://x.com/HUZHENSHENG" : nil
        if let t = target { DispatchQueue.main.async { openURL(t) } }
    }

    // MARK: global hotkeys ⌘⇧R / ⌘⇧+ / ⌘⇧−
    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evt, _ in
            var hk = EventHotKeyID()
            GetEventParameter(evt, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            switch hk.id {
            case 1: wakeSoft()
            case 2: if let d = physicalExternals().first { stepScaled(d, larger: true) }
            case 3: if let d = physicalExternals().first { stepScaled(d, larger: false) }
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
