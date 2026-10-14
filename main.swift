// WakeDisplay — macOS 菜单栏小工具：唤醒黑屏的 USB-C 外接显示器 / 解锁隐藏 HiDPI 缩放
// Author: 胡震生 Jason Hu (@HUZHENSHENG · 0xBig2)  ·  MIT License
// https://github.com/jasonhuzhensheng/WakeDisplay
// 编译：见 build.sh（只需 Xcode Command Line Tools）
import Cocoa
import Carbon
import IOKit
import IOKit.pwr_mgt

// MARK: - 核心：唤醒逻辑

/// 等价于系统设置里按住 Option 出现的「检测显示器」：让所有显示控制器重新探测/握手
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

/// 向电源管理声明“用户活动”，强制点亮所有屏幕（相当于 caffeinate -u）
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

/// 需要管理员权限的命令：弹系统密码框
func sudoShell(_ cmd: String) -> (ok: Bool, out: String) {
    let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let src = "do shell script \"\(escaped)\" with administrator privileges"
    var err: NSDictionary?
    let res = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err = err { return (false, "\(err[NSAppleScript.errorMessage] ?? err)") }
    return (true, res?.stringValue ?? "")
}


// MARK: - 手段二：镜像开关，强制重新建立 DP 链路（公开 CoreGraphics API）
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

// MARK: - 手段三：DDC/CI 直接给显示器发「开机」指令（Apple Silicon，经 USB-C/DP I²C）
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
        for _ in 0..<3 {   // 重试几次，面板休眠时第一包常被吞
            data.withUnsafeMutableBytes { _ = IOAVServiceWriteI2C(av, 0x37, 0x51, $0.baseAddress!, 6) }
            usleep(50_000)
        }
        IOObjectRelease(svc)
    }
}
func ddcPowerOn() { ddcWrite(vcp: 0xD6, value: 1) }   // VCP D6 = Power Mode，1 = On

/// 一级唤醒：用户活动 + DDC 开机 + 重新探测 + 镜像开关
func wakeSoft() {
    declareUserActivity()
    ddcPowerOn()
    probeDisplays()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { mirrorToggle() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { ddcPowerOn(); probeDisplays(); declareUserActivity() }
}

/// 二级唤醒：先让所有屏幕睡眠，再唤醒，强制雷电/USB-C 端口重新枚举
func wakeHard() {
    DispatchQueue.global().async {
        shell("pmset displaysleepnow")
        Thread.sleep(forTimeInterval: 3)
        DispatchQueue.main.async { wakeSoft() }
    }
}


// MARK: - 缩放 / 字体大小（列出系统隐藏的 HiDPI 模式，等价于系统设置里的「更大/更小文本」）
struct ScaleMode {
    let mode: CGDisplayMode
    var w: Int { mode.width }; var h: Int { mode.height }
    var hidpi: Bool { mode.pixelWidth > mode.width }
    var hz: Int { Int(mode.refreshRate.rounded()) }
    var title: String { "\(w) × \(h)" + (hidpi ? "  HiDPI（清晰）" : "") + (hz > 0 ? "  \(hz)Hz" : "") }
}
func scaleModes(for d: CGDirectDisplayID) -> [ScaleMode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let all = CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] else { return [] }
    let cur = CGDisplayCopyDisplayMode(d)
    var seen = Set<String>(); var out: [ScaleMode] = []
    for m in all where m.isUsableForDesktopGUI() {
        // 同分辩率只保留一个：优先当前刷新率，其次最高刷新率
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
    if #available(macOS 10.15, *) {
        for s in NSScreen.screens where (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d { return s.localizedName }
    }
    return "显示器 \(d)"
}
func setMode(_ d: CGDirectDisplayID, _ m: CGDisplayMode) {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
    CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
    CGCompleteDisplayConfiguration(cfg, .permanently)
}
/// 「更大文本」= 切到下一个更低的 HiDPI 分辨率；「更小文本」反之
func stepText(_ d: CGDirectDisplayID, larger: Bool) {
    let modes = scaleModes(for: d).filter { $0.hidpi }.sorted { $0.w > $1.w }
    guard let cur = CGDisplayCopyDisplayMode(d), !modes.isEmpty else { return }
    let idx = modes.firstIndex { $0.w == cur.width && $0.h == cur.height && $0.hidpi } ?? (larger ? -1 : modes.count)
    let next = larger ? idx + 1 : idx - 1
    guard modes.indices.contains(next) else { return }
    setMode(d, modes[next].mode)
}

// MARK: - 状态栏 App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var preventSleepID: IOPMAssertionID = 0
    var preventSleepItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var hotKeyRef: EventHotKeyRef?
    var autoWakeTimer: Timer?
    var autoWakeItem: NSMenuItem!

    let launchAgent = NSString(string: "~/Library/LaunchAgents/com.jason.wakedisplay.plist").expandingTildeInPath

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "display", accessibilityDescription: "WakeDisplay")
            btn.action = #selector(statusClicked(_:))
            btn.target = self
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        registerHotKey()
    }

    /// 左键 = 直接唤醒；右键 = 打开菜单
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

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "🔆 唤醒显示器    ⌘⇧R", action: #selector(actWakeSoft), keyEquivalent: "")
        m.addItem(withTitle: "🔁 强制重置（关屏 → 重新握手）", action: #selector(actWakeHard), keyEquivalent: "")
        m.addItem(.separator())
        preventSleepItem = NSMenuItem(title: "☕️ 阻止显示器休眠", action: #selector(actToggleSleep), keyEquivalent: "")
        preventSleepItem.state = preventSleepID != 0 ? .on : .off
        m.addItem(preventSleepItem)
        autoWakeItem = NSMenuItem(title: "🤖 自动唤醒（外屏休眠而电脑在用时自动点亮）", action: #selector(actToggleAutoWake), keyEquivalent: "")
        autoWakeItem.state = autoWakeTimer != nil ? .on : .off
        m.addItem(autoWakeItem)
        m.addItem(.separator())
        for d in externalDisplays() {
            let sub = NSMenu()
            let bigger = NSMenuItem(title: "更大文本  ⌘⇧+", action: #selector(actLarger(_:)), keyEquivalent: ""); bigger.representedObject = d; bigger.target = self; sub.addItem(bigger)
            let smaller = NSMenuItem(title: "更小文本  ⌘⇧−", action: #selector(actSmaller(_:)), keyEquivalent: ""); smaller.representedObject = d; smaller.target = self; sub.addItem(smaller)
            sub.addItem(.separator())
            let cur = CGDisplayCopyDisplayMode(d)
            let modes = scaleModes(for: d)
            if !modes.contains(where: { $0.hidpi }) {
                let note = NSMenuItem(title: "⚠️ 此显示器没有可用的 HiDPI 模式（见帮助）", action: #selector(actHiDPIHelp), keyEquivalent: ""); note.target = self; sub.addItem(note)
                sub.addItem(.separator())
            }
            for sm in modes {
                let it = NSMenuItem(title: sm.title, action: #selector(actSetMode(_:)), keyEquivalent: "")
                it.representedObject = [d, sm.mode] as [Any]; it.target = self
                if let c = cur, c.width == sm.w, c.height == sm.h, (c.pixelWidth > c.width) == sm.hidpi { it.state = .on }
                sub.addItem(it)
            }
            let parent = NSMenuItem(title: "🔍 缩放 / 字体大小 — \(displayName(d))", action: nil, keyEquivalent: "")
            m.addItem(parent); m.setSubmenu(sub, for: parent)
        }
        m.addItem(.separator())
        m.addItem(withTitle: "⚡️ 写入防断连电源策略（sudo pmset）", action: #selector(actApplyPmset), keyEquivalent: "")
        m.addItem(withTitle: "↩️ 恢复系统默认电源策略", action: #selector(actRestorePmset), keyEquivalent: "")
        m.addItem(withTitle: "🔍 查看当前电源参数", action: #selector(actShowPmset), keyEquivalent: "")
        m.addItem(withTitle: "🧹 清除显示器缓存（EDID）并重启…", action: #selector(actResetEDID), keyEquivalent: "")
        m.addItem(.separator())
        loginItem = NSMenuItem(title: "开机自动启动", action: #selector(actToggleLogin), keyEquivalent: "")
        loginItem.state = FileManager.default.fileExists(atPath: launchAgent) ? .on : .off
        m.addItem(loginItem)
        m.addItem(withTitle: "关于 WakeDisplay…", action: #selector(actAbout), keyEquivalent: "")
        m.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for i in m.items where i.target == nil { i.target = self }
        return m
    }

    // MARK: 菜单动作
    @objc func actWakeSoft() { wakeSoft(); flash() }
    @objc func actWakeHard() { wakeHard() }

    @objc func actLarger(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepText(d, larger: true) } }
    @objc func actSmaller(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepText(d, larger: false) } }
    @objc func actSetMode(_ s: NSMenuItem) {
        guard let arr = s.representedObject as? [Any], let d = arr[0] as? CGDirectDisplayID else { return }
        setMode(d, arr[1] as! CGDisplayMode)
    }
    @objc func actHiDPIHelp() {
        info("没有 HiDPI 模式怎么办", """
        macOS 只对像素密度足够高的显示器（通常 ≥ 4K）自动提供 HiDPI 缩放模式。
        1080p / 2K 便携屏一般只有原生模式，所以系统设置里也没有「更大文本」。

        可选方案：
        • 先在本菜单里选一个较低的非 HiDPI 分辩率（如 1600×900），字体会变大但略模糊；
        • 要「既大又清晰」，需要创建一块虚拟 HiDPI 屏再镜像到物理屏（BetterDisplay 的做法），
          本工具后续可加入该功能。
        """)
    }

    /// 每 5 秒检查：外屏在线但处于 asleep，而内屏是醒着的 → 自动唤醒
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
        guard confirm("写入电源策略", "将执行：\nsudo pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0\n\n效果：合盖/锁屏时不再切断 USB-C 供电。笔记本用电池时会更耗电。继续？") else { return }
        let r = sudoShell("/usr/bin/pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0")
        info(r.ok ? "已写入" : "失败", r.ok ? shell("pmset -g | egrep ' sleep| standby|autopoweroff|powernap'") : r.out)
    }

    @objc func actRestorePmset() {
        guard confirm("恢复默认", "将执行 sudo pmset restoredefaults，继续？") else { return }
        let r = sudoShell("/usr/bin/pmset restoredefaults")
        info(r.ok ? "已恢复默认" : "失败", r.out)
    }

    @objc func actShowPmset() { info("pmset -g", shell("pmset -g")) }

    @objc func actResetEDID() {
        guard confirm("清除显示器缓存", "将删除 /Library/Preferences/com.apple.windowserver.displays.plist 及用户级显示配置，然后重启 Mac。\n不影响个人数据，但显示器排列/缩放设置会重置。继续？") else { return }
        let r = sudoShell("/bin/rm -f /Library/Preferences/com.apple.windowserver.displays.plist ~/Library/Preferences/ByHost/com.apple.windowserver*.plist; /sbin/shutdown -r now")
        if !r.ok { info("失败", r.out) }
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

    // MARK: 全局快捷键 ⌘⇧R
    func registerHotKey() {
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
        var r1: EventHotKeyRef?, r2: EventHotKeyRef?, r3: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x57414B45, id: 1), GetApplicationEventTarget(), 0, &r1)
        RegisterEventHotKey(UInt32(kVK_ANSI_Equal), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x57414B45, id: 2), GetApplicationEventTarget(), 0, &r2)
        RegisterEventHotKey(UInt32(kVK_ANSI_Minus), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x57414B45, id: 3), GetApplicationEventTarget(), 0, &r3)
        hotKeyRef = r1
    }

    @objc func actAbout() {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let a = NSAlert()
        a.messageText = "WakeDisplay \(ver)"
        a.informativeText = """
        macOS 菜单栏小工具：一键唤醒黑屏的 USB-C 外接显示器，解锁系统隐藏的 HiDPI 缩放模式。

        作者：大老二 胡震生（Jason Hu）
        X：@HUZHENSHENG  ·  0xBig2

        开发工具：Claude Fable 5.1（Anthropic）
        开源协议：MIT
        """
        a.addButton(withTitle: "打开 GitHub")
        a.addButton(withTitle: "关注 X @HUZHENSHENG")
        a.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(URL(string: "https://github.com/jasonhuzhensheng/WakeDisplay")!)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(URL(string: "https://x.com/HUZHENSHENG")!)
        default: break
        }
    }

    // MARK: 对话框
    func confirm(_ t: String, _ msg: String) -> Bool {
        let a = NSAlert(); a.messageText = t; a.informativeText = msg
        a.addButton(withTitle: "继续"); a.addButton(withTitle: "取消")
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
app.setActivationPolicy(.accessory)   // 不显示 Dock 图标
app.run()
