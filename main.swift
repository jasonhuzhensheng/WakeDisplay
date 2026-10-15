// WakeDisplay — macOS menu-bar utility: wake dark USB-C external displays / unlock hidden HiDPI scaling
// WakeDisplay — macOS 菜单栏小工具：唤醒黑屏的 USB-C 外接显示器 / 解锁隐藏 HiDPI 缩放
// Author: 胡震生 Jason Hu (@HUZHENSHENG · 0xBig2)  ·  MIT License
// https://github.com/jasonhuzhensheng/WakeDisplay
// Build: see build.sh (Xcode Command Line Tools only)
import Cocoa
import Carbon
import IOKit
import IOKit.pwr_mgt
import Metal
import QuartzCore

// Localization (Lang, L(), translations) lives in Localization.swift


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

/// Hovering over / clicking the menu-bar icon: wake right away (off the main thread, so the menu opens instantly).
/// Throttled so opening the menu repeatedly doesn't spam the monitors with DDC commands.
private var lastClickWake = Date.distantPast
func wakeOnClick() {
    guard Date().timeIntervalSince(lastClickWake) > 3 else { return }
    lastClickWake = Date()
    let q = DispatchQueue.global(qos: .userInitiated)
    q.async { declareUserActivity(); ddcPowerOn(); probeDisplays() }
    q.asyncAfter(deadline: .now() + 1.5) { ddcPowerOn(); probeDisplays() }
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

/// The mode that drives the panel at its highest real pixel count (= native resolution).
/// Some panels (e.g. 2880×1800 portables) only expose native pixels through a HiDPI mode such as
/// "1440×900 HiDPI", so compare backing pixels, not logical size. Prefer the current refresh rate.
func nativeMode(_ d: CGDirectDisplayID) -> CGDisplayMode? {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let all = (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
    let cur = CGDisplayCopyDisplayMode(d)
    return all.max { a, b in
        let pa = a.pixelWidth * a.pixelHeight, pb = b.pixelWidth * b.pixelHeight
        if pa != pb { return pa < pb }
        if let c = cur, a.refreshRate != b.refreshRate {
            return abs(a.refreshRate - c.refreshRate) > abs(b.refreshRate - c.refreshRate)
        }
        return (a.pixelWidth > a.width) && !(b.pixelWidth > b.width)   // tie: prefer the HiDPI variant
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
    settings.modes = logicalSizes(W, H).map { CGVirtualDisplayMode(width: UInt($0.w * 2), height: UInt($0.h * 2), refreshRate: CGFloat(hz)) }
    if !vd.apply(settings) {
        settings.modes = logicalSizes(W, H).map { CGVirtualDisplayMode(width: UInt($0.w * 2), height: UInt($0.h * 2), refreshRate: 60) }
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
    PerDisplay.saveMode(physical)
    if hidpiVirtuals[physical] != nil, let m = CGDisplayCopyDisplayMode(t) {
        UserDefaults.standard.set(m.width, forKey: displayKey(physical))
    }
}


// MARK: - Outdoor mode (built-in display): max brightness + XDR boost
//
// 1. Push the built-in panel's backlight to 100% (private DisplayServices, loaded at runtime).
// 2. On Liquid Retina XDR MacBook Pros, show a 1-pixel EDR (HDR) layer so macOS unlocks the panel's
//    extra headroom, then scale the display's gamma table above 1.0. The whole SDR desktop gets
//    ~1.6× brighter (≈1000 nits full-screen instead of 500). Same technique as BrightIntosh.
// Turning it off restores the previous brightness and the normal gamma table.

typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
let dsGetBrightness: DSGetBrightnessFn? = dsHandle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: DSGetBrightnessFn.self) }
let dsSetBrightness: DSSetBrightnessFn? = dsHandle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: DSSetBrightnessFn.self) }

func builtinDisplay() -> CGDirectDisplayID? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
}
func screenFor(_ d: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d }
}

final class OutdoorMode {
    private(set) var isOn = false
    private(set) var boost: Float = 1.0          // gamma multiplier actually applied
    private var savedBrightness: Float?
    private var window: NSWindow?
    private var metalLayer: CAMetalLayer?
    private lazy var device = MTLCreateSystemDefaultDevice()   // created only when Outdoor Mode is first used
    private lazy var queue = device?.makeCommandQueue()
    private var timer: Timer?
    private var display: CGDirectDisplayID = 0

    /// How much extra brightness this panel can give (1.0 = none, i.e. not an XDR display)
    static func available(_ screen: NSScreen) -> Float {
        Float(min(screen.maximumPotentialExtendedDynamicRangeColorComponentValue, 1.6))
    }

    /// Manual toggle (menu / hotkey / URL); the light-sensor automation uses start()/stop() directly
    func toggle() { isOn ? stop() : start(); AutoOutdoor.manualToggled(isOnNow: isOn) }

    func start() {
        guard !isOn, let d = builtinDisplay() else { return }
        EInk.stop(d, quiet: true)
        display = d
        isOn = true
        var cur: Float = 0
        if let get = dsGetBrightness, get(d, &cur) == 0 { savedBrightness = cur }
        _ = dsSetBrightness?(d, 1.0)

        if let screen = screenFor(d) {
            boost = OutdoorMode.available(screen)
            if boost > 1.01 { captureBaseTable(); showEDRPixel(on: screen) }
        }
        ticks = 0
        apply(force: true)
        // macOS resets brightness (auto-brightness) and gamma (Night Shift, reconfig) now and then → re-check.
        // Cheap reads every 2 s; writes only when something actually changed.
        timer = every(2, tolerance: 0.5) { [weak self] in self?.apply() }
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil; metalLayer = nil
        if !baseR.isEmpty { CGSetDisplayTransferByTable(display, UInt32(baseR.count), baseR, baseG, baseB) }  // back to normal
        baseR = []; baseG = []; baseB = []; boostR = []; boostG = []; boostB = []
        if let b = savedBrightness { _ = dsSetBrightness?(display, b) }
        savedBrightness = nil
        boost = 1.0
    }

    /// Re-apply brightness / EDR / gamma right away (e.g. after the Mac wakes)
    func refresh() { ticks = 0; apply(force: true) }

    private var ticks = 0
    private func apply(force: Bool = false) {
        guard isOn else { return }
        var cur: Float = 0
        if force || dsGetBrightness?(display, &cur) != 0 || cur < 0.995 { _ = dsSetBrightness?(display, 1.0) }
        // The EDR frame stays on screen by itself; repaint it only occasionally (every ~10 s)
        if force || ticks % 5 == 0 { renderEDR() }
        ticks &+= 1
        guard boost > 1.01, !boostR.isEmpty else { return }
        // Base table × boost (precomputed). Values > 1.0 only take effect while EDR is active.
        if !force, gammaStillApplied() { return }
        CGSetDisplayTransferByTable(display, UInt32(boostR.count), boostR, boostG, boostB)
    }

    /// Compare the live gamma table with ours (a read is much cheaper than a write + recomposite)
    private func gammaStillApplied() -> Bool {
        let n = boostR.count
        var r = [CGGammaValue](repeating: 0, count: n), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, UInt32(n), &r, &g, &b, &count) == .success, Int(count) == n else { return false }
        let i = n - 1, m = n / 2
        return abs(r[i] - boostR[i]) < 0.002 && abs(g[m] - boostG[m]) < 0.002 && abs(b[i] - boostB[i]) < 0.002
    }

    private var baseR: [CGGammaValue] = [], baseG: [CGGammaValue] = [], baseB: [CGGammaValue] = []
    private var boostR: [CGGammaValue] = [], boostG: [CGGammaValue] = [], boostB: [CGGammaValue] = []
    /// Read the normal (un-boosted) gamma table once, so re-applying never flickers
    private func captureBaseTable() {
        let cap: UInt32 = 256
        var r = [CGGammaValue](repeating: 0, count: Int(cap)), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, cap, &r, &g, &b, &count) == .success, count > 0 else { return }
        baseR = Array(r.prefix(Int(count))); baseG = Array(g.prefix(Int(count))); baseB = Array(b.prefix(Int(count)))
        let k = CGGammaValue(boost)
        boostR = baseR.map { $0 * k }; boostG = baseG.map { $0 * k }; boostB = baseB.map { $0 * k }
    }

    /// A 1×1-point always-on-top window with EDR content: this is what makes macOS unlock XDR headroom
    private func showEDRPixel(on screen: NSScreen) {
        let f = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
        let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let ml = CAMetalLayer()
        ml.device = device
        ml.pixelFormat = .rgba16Float
        ml.wantsExtendedDynamicRangeContent = true
        ml.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        ml.isOpaque = false
        ml.drawableSize = CGSize(width: 2, height: 2)
        ml.frame = v.bounds
        v.wantsLayer = true
        v.layer = ml
        w.contentView = v
        w.setFrame(f, display: true)
        w.orderFrontRegardless()
        window = w
        metalLayer = ml
    }

    private func renderEDR() {
        guard let ml = metalLayer, let q = queue, let drawable = ml.nextDrawable(),
              let cb = q.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let v = Double(boost)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1)
        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
let outdoor = OutdoorMode()

// MARK: - E-ink mode (for reading), per display: warm "paper" tint, lifted blacks, softer contrast
//
// Applied with a per-display gamma formula, so each screen can be switched on its own and the
// others stay in full colour. (macOS can only turn true grayscale on for all screens at once,
// so this mode mutes colours into paper tones instead.) Off = ColorSync gamma restored.

enum EInk {
    private(set) static var displays = Set<CGDirectDisplayID>()
    static var isOn: Bool { !displays.isEmpty }
    private static var observing = false

    /// Hotkey / URL: toggle the screen under the mouse pointer
    static func toggleUnderMouse() {
        let p = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
        guard let id = scr?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
        toggle(id)
    }

    static func toggle(_ d: CGDirectDisplayID) { displays.contains(d) ? stop(d) : start(d) }

    static func start(_ d: CGDirectDisplayID) {
        guard !displays.contains(d) else { return }
        if d == builtinDisplay(), outdoor.isOn { outdoor.stop() }   // both drive the built-in panel's gamma
        displays.insert(d)
        apply()
        if !observing {                             // macOS resets gamma on wake / reconfiguration
            observing = true
            let re: (Notification) -> Void = { _ in if isOn { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { apply() } } }
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: re)
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: re)
        }
        (NSApp.delegate as? AppDelegate)?.updateIcon()
        WakeReminder.show("📖 " + L("E-ink Mode is on"), displayName(d) + " · " + L("Press ⌃⌥⌘E to switch back to color"))
    }

    static func stop(_ d: CGDirectDisplayID, quiet: Bool = false) {
        guard displays.remove(d) != nil else { return }
        CGDisplayRestoreColorSyncSettings()         // resets every display…
        apply()                                     // …so re-tint the ones still in e-ink mode
        if outdoor.isOn { outdoor.refresh() }
        (NSApp.delegate as? AppDelegate)?.updateIcon()
        if !quiet { WakeReminder.show("🎨 " + L("Back to color"), displayName(d)) }
    }

    static func stopAll() {
        guard isOn else { return }
        displays.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    private static func apply() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        let online = Set(ids.prefix(Int(n)))
        displays.formIntersection(online)           // forget unplugged screens
        for d in displays {
            //                              min   max   gamma   → paper white, ink ≈ deep warm grey
            CGSetDisplayTransferByFormula(d, 0.12, 0.95, 1.2,
                                             0.11, 0.91, 1.2,
                                             0.09, 0.80, 1.2)
        }
    }
}

// MARK: - Menu-bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var preventSleepID: IOPMAssertionID = 0
    var autoWakeTimer: Timer?
    var telemetryTimer: Timer?
    var hotKeyRefs: [EventHotKeyRef?] = []

    let launchAgent = NSString(string: "~/Library/LaunchAgents/com.jason.wakedisplay.plist").expandingTildeInPath

    func applicationDidFinishLaunching(_ n: Notification) {
        // On notched MacBooks, overflowing menu-bar icons hide behind the notch, and a newly launched
        // app lands nearest to it. Ask macOS to place ours at the far right (next to Control Center)
        // the first time; after that, the user's own ⌘-drag position is remembered.
        let posKey = "NSStatusItem Preferred Position WakeDisplay"
        if !UserDefaults.standard.bool(forKey: "didSetInitialPosition") {
            UserDefaults.standard.set(0.0, forKey: posKey)
            UserDefaults.standard.set(true, forKey: "didSetInitialPosition")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "WakeDisplay"
        updateIcon()
        // Hover wakes the external display; a click also opens the menu; contents are rebuilt each time it opens
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // Hovering over the icon is enough to wake the external display (no click needed)
        if let b = statusItem.button {
            b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                             owner: self, userInfo: nil))
        }
        registerHotKeys()
        CrashReporter.start()
        WakeReminder.start()
        if AutoOutdoor.enabled { AutoOutdoor.start() }
        SoftDisconnect.reconnectAll()          // never leave a monitor switched off from a previous run
        startDisplayWatcher()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { PerDisplay.restoreAll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            Telemetry.send("App.launched")
            Telemetry.dailyActiveIfNeeded()
        }
        Updater.start()
        // One low-priority hourly tick for all background housekeeping (tolerance lets macOS batch it)
        telemetryTimer = every(3600, tolerance: 600) {
            Telemetry.dailyActiveIfNeeded()
            Updater.hourlyTick()
        }
    }

    func applicationWillTerminate(_ n: Notification) { outdoor.stop(); EInk.stopAll(); SoftDisconnect.reconnectAll(); CrashReporter.cleanExit() }

    /// URL commands (handy for Shortcuts / scripts): wakedisplay://wake | reset | outdoor | larger | smaller | menu
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "wakedisplay" {
            Telemetry.feature(url.host ?? "unknown", source: "url")
            switch url.host ?? "" {
            case "wake":    wakeSoft()
            case "reset":   wakeHard()
            case "outdoor": actToggleOutdoor()
            case "eink":    actToggleEInk()
            case "larger":  if let d = physicalExternals().first { stepScaled(d, larger: true) }
            case "smaller": if let d = physicalExternals().first { stepScaled(d, larger: false) }
            case "menu":    popMenuAtMouse()
            default: break
            }
        }
    }

    /// ⌃⌥⌘M: open the menu at the mouse pointer (works even if the icon is hidden behind the notch)
    func popMenuAtMouse() {
        let m = buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func mouseEntered(with event: NSEvent) { playWakeAnimation(); wakeOnClick() }

    /// Hover feedback: the icon goes from dim to bright while the sun rises (0.5 s)
    private var animTimer: Timer?
    func playWakeAnimation() {
        guard animTimer == nil, let b = statusItem.button else { return }
        let start = Date(), duration = 0.5
        b.alphaValue = 0.3
        updateIcon(rise: 0)
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            let p = min(1, Date().timeIntervalSince(start) / duration)
            let e = 1 - pow(1 - p, 3)                       // ease-out
            b.alphaValue = 0.3 + 0.7 * e
            self?.updateIcon(rise: e)
            if p >= 1 { t.invalidate(); self?.animTimer = nil; b.alphaValue = 1; self?.updateIcon() }
        }
        RunLoop.main.add(animTimer!, forMode: .common)   // keep animating while the menu is open
    }
    @objc func mouseExited(with event: NSEvent) {}

    func menuNeedsUpdate(_ menu: NSMenu) {
        wakeOnClick()          // clicking the icon wakes the external display and opens the menu
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

    /// "📖 E-ink Mode" toggle for one screen (shown in Advanced ▸ External / Built-in)
    func einkItem(_ d: CGDirectDisplayID, named: Bool) -> NSMenuItem {
        let title = "📖 " + L("E-ink Mode (for reading)  ⌃⌥⌘E") + (named ? " — " + displayName(d) : "")
        return item(title, #selector(actToggleEInkDisplay(_:)), state: EInk.displays.contains(d), obj: NSNumber(value: d))
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item("🔆 " + L("Wake Display    ⌘⇧R"), #selector(actWakeSoft)))
        m.addItem(item("☀️ " + L("Outdoor Mode (max brightness)  ⌃⌥⌘B"), #selector(actToggleOutdoor), state: outdoor.isOn))
        var scaleItems: [NSMenuItem] = []     // → top of ⚙️ Advanced
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
            parent.submenu = sub
            scaleItems.append(parent)
        }
        if let quick = QuickLayout.menuItem() { m.addItem(quick) }
        m.addItem(.separator())

        // ── Everything else lives in ⚙️ Advanced (level 2), ordered by how often it is used ──
        // External Displays ▸ : scaling first, then wake tools
        var extHead: [NSMenuItem] = scaleItems
        if !scaleItems.isEmpty { extHead.append(.separator()) }
        extHead += [
            item("🔁 " + L("Force Reset (sleep → re-handshake, screens blink)"), #selector(actWakeHard)),
            item("🤖 " + L("Auto-Wake (external asleep while Mac in use)"), #selector(actToggleAutoWake), state: autoWakeTimer != nil),
        ]
        // E-ink Mode per external display (level 3)
        let exts = physicalExternals()
        if !exts.isEmpty { extHead.append(.separator()) }
        for d in exts {
            extHead.append(einkItem(d, named: exts.count > 1))
        }
        // Built-in Display ▸ : Outdoor Mode (+ Auto Outdoor Mode added by AdvancedMenu)
        var builtinHead: [NSMenuItem] = [
            item("☀️ " + L("Outdoor Mode (max brightness)  ⌃⌥⌘B"), #selector(actToggleOutdoor), state: outdoor.isOn),
        ]
        if let b = builtinDisplay() { builtinHead.append(einkItem(b, named: false)) }

        // Level 3: Maintenance ▸
        let maint = NSMenu()
        maint.addItem(item("⚡️ " + L("Apply Anti-Disconnect Power Policy (sudo pmset)"), #selector(actApplyPmset)))
        maint.addItem(item("↩️ " + L("Restore Default Power Policy"), #selector(actRestorePmset)))
        maint.addItem(item("🔍 " + L("Show Current Power Settings"), #selector(actShowPmset)))
        maint.addItem(.separator())
        maint.addItem(item("🧹 " + L("Reset Display Cache (EDID) & Restart…"), #selector(actResetEDID)))
        let maintParent = NSMenuItem(title: "🛠 " + L("Maintenance"), action: nil, keyEquivalent: "")
        maintParent.submenu = maint

        // Level 3: Language ▸
        let langSub = NSMenu()
        for l in Lang.allCases {
            let title = l == .auto ? L("Automatic (System)") : (langNativeNames[l] ?? l.rawValue)
            langSub.addItem(item(title, #selector(actSetLang(_:)), state: currentLang == l, obj: l.rawValue))
            if l == .auto { langSub.addItem(.separator()) }
        }
        let langTitle = effectiveLang() == .en ? "Language" : L("Language") + " · Language"
        let langParent = NSMenuItem(title: "🌐 " + langTitle, action: nil, keyEquivalent: "")
        langParent.submenu = langSub

        // Level 3: About ▸ (Updates ▸ and Sponsor ▸ Crypto ▸ go to levels 4–5)
        let aboutSub = NSMenu()
        aboutSub.addItem(item(L("About WakeDisplay…"), #selector(actAbout)))
        let upd = NSMenu()
        upd.addItem(item(L("Check for Updates…"), #selector(actCheckUpdates)))
        upd.addItem(item(L("Install Updates Automatically"), #selector(actToggleAutoUpdate), state: Updater.autoUpdate))
        upd.addItem(.separator())
        upd.addItem(ExtrasMenu.shared.whatsNewItem())
        let updParent = NSMenuItem(title: "🔄 " + L("Updates"), action: nil, keyEquivalent: "")
        updParent.submenu = upd
        aboutSub.addItem(updParent)
        aboutSub.addItem(.separator())
        aboutSub.addItem(ExtrasMenu.shared.reportIssueItem())
        aboutSub.addItem(ExtrasMenu.shared.sponsorMenu())
        aboutSub.addItem(ExtrasMenu.shared.privacyMenu())
        aboutSub.addItem(.separator())
        let ver = NSMenuItem(title: "WakeDisplay v\(Updater.currentVersion)", action: nil, keyEquivalent: "")
        ver.isEnabled = false
        aboutSub.addItem(ver)
        let aboutParent = NSMenuItem(title: "ℹ️ " + L("About"), action: nil, keyEquivalent: "")
        aboutParent.submenu = aboutSub

        let general: [NSMenuItem] = [
            item("☕️ " + L("Prevent Display Sleep"), #selector(actToggleSleep), state: preventSleepID != 0),
            maintParent,
            .separator(),
            langParent,
            item(L("Launch at Login"), #selector(actToggleLogin), state: FileManager.default.fileExists(atPath: launchAgent)),
            aboutParent,
            .separator(),
            NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        m.addItem(AdvancedMenu.shared.build(externalHead: extHead, builtinHead: builtinHead, general: general))
        m.addItem(item("📤 " + L("Share WakeDisplay…"), #selector(actShare)))
        return m
    }

    // MARK: actions
    @objc func actWakeSoft() { wakeSoft(); Telemetry.feature("wake") }
    @objc func actWakeHard() { wakeHard(); Telemetry.feature("forceReset") }

    @objc func actToggleEInk() {
        EInk.toggleUnderMouse()
        if EInk.isOn { Telemetry.feature("einkMode") }
    }
    @objc func actToggleEInkDisplay(_ sender: NSMenuItem) {
        guard let d = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        EInk.toggle(d)
        if EInk.isOn { Telemetry.feature("einkMode") }
    }

    @objc func actToggleOutdoor() {
        outdoor.toggle()
        if outdoor.isOn { Telemetry.feature("outdoorMode") }
        updateIcon()
        if outdoor.isOn && outdoor.boost <= 1.01 {
            info(L("Outdoor Mode"), L("Brightness set to 100%. This display has no XDR headroom, so no extra boost is available beyond that."))
        }
    }

    @objc func actShare() {
        // Let the menu finish closing before anchoring the share sheet to the icon
        DispatchQueue.main.async { ShareController.shared.show(from: self.statusItem.button) }
    }
    @objc func actCheckUpdates() { Updater.checkInteractively() }
    @objc func actToggleAutoUpdate() { Updater.autoUpdate.toggle() }
    @objc func actToggleTelemetry() { Telemetry.enabled.toggle() }

    @objc func actSetLang(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String, let l = Lang(rawValue: code) else { return }
        currentLang = l
        UserDefaults.standard.set(code, forKey: "lang")   // remembered across launches
    }

    @objc func actLarger(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepScaled(d, larger: true) } }
    @objc func actSmaller(_ s: NSMenuItem) { if let d = s.representedObject as? CGDirectDisplayID { stepScaled(d, larger: false) } }
    @objc func actSetMode(_ s: NSMenuItem) {
        guard let arr = s.representedObject as? [Any], arr.count == 2, let d = arr[0] as? CGDirectDisplayID else { return }
        let m = arr[1] as! CGDisplayMode
        setMode(scalingTarget(d), m)
        if hidpiVirtuals[d] != nil { UserDefaults.standard.set(m.width, forKey: displayKey(d)) }
        else { PerDisplay.saveMode(d) }
    }
    @objc func actToggleSharp(_ s: NSMenuItem) {
        guard let d = s.representedObject as? CGDirectDisplayID else { return }
        if hidpiVirtuals[d] != nil { disableSharpScaling(d) }
        else if enableSharpScaling(d) { Telemetry.feature("sharpScaling") }
        else { info(L("Failed"), L("Could not create the HiDPI virtual display on this Mac.")) }
    }
    @objc func actHiDPIHelp() { info(L("No HiDPI modes — what now?"), L(hidpiHelpEN)) }

    /// Every 5 s: built-in awake but an external display asleep → wake
    @objc func actToggleAutoWake() {
        if let t = autoWakeTimer { t.invalidate(); autoWakeTimer = nil; return }
        Telemetry.feature("autoWake")
        autoWakeTimer = every(5, tolerance: 1.5) {
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
        updateIcon()
    }

    /// Menu-bar icon, drawn in code (no image files): a display with a rising sun.
    /// Outdoor Mode on → solid sun; Prevent Sleep on → small dot top-right. Template image, so it follows light/dark.
    /// `rise` 0…1: how far the sun has risen (used by the hover animation; 1 = normal icon)
    func updateIcon(rise: CGFloat = 1) {
        let sunOn = outdoor.isOn, keepAwake = preventSleepID != 0
        let drop = (1 - rise) * 4.5
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let screen = NSBezierPath(roundedRect: NSRect(x: 2.25, y: 3.25, width: 13.5, height: 9.5), xRadius: 1.6, yRadius: 1.6)
            screen.lineWidth = 1.5; screen.stroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 3, y: 4, width: 12, height: 8.6)).addClip()   // sun rises from behind the bezel
            let tr = NSAffineTransform(); tr.translateX(by: 0, yBy: drop); tr.concat()
            let sun = NSBezierPath()
            sun.appendArc(withCenter: NSPoint(x: 9, y: 12), radius: 3.2, startAngle: 180, endAngle: 0, clockwise: false)
            if sunOn { sun.close(); sun.fill() } else { sun.lineWidth = 1.4; sun.stroke() }
            let rays = NSBezierPath(); rays.lineWidth = 1.3; rays.lineCapStyle = .round
            for (a, b) in [((9.0, 6.6), (9.0, 7.6)), ((5.6, 8.4), (6.4, 9.0)), ((12.4, 8.4), (11.6, 9.0))] {
                rays.move(to: NSPoint(x: a.0, y: a.1)); rays.line(to: NSPoint(x: b.0, y: b.1))
            }
            rays.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let stand = NSBezierPath(); stand.lineWidth = 1.5; stand.lineCapStyle = .round
            stand.move(to: NSPoint(x: 6, y: 15.6)); stand.line(to: NSPoint(x: 12, y: 15.6)); stand.stroke()
            if keepAwake { NSBezierPath(ovalIn: NSRect(x: 13.6, y: 0.4, width: 4, height: 4)).fill() }
            if EInk.isOn { NSBezierPath(rect: NSRect(x: 0.4, y: 0.4, width: 3.6, height: 3.6)).fill() }   // e-ink: small square badge
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "WakeDisplay"
        statusItem.button?.image = img
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
              <key>AbandonProcessGroup</key><true/>
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
        // Anonymous-stats switch lives here, as a checkbox under the text
        a.showsSuppressionButton = true
        a.suppressionButton?.title = L("Send Anonymous Usage Stats")
        a.suppressionButton?.state = Telemetry.enabled ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        let resp = a.runModal()
        Telemetry.enabled = (a.suppressionButton?.state == .on)
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
            case 4: outdoor.toggle()
            case 5: (NSApp.delegate as? AppDelegate)?.popMenuAtMouse()
            case 6: DDC.step(10)
            case 7: DDC.step(-10)
            case 8: EInk.toggleUnderMouse()
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
        var ref4: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x57414B45, id: 4), GetApplicationEventTarget(), 0, &ref4)
        hotKeyRefs.append(ref4)
        var ref8: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_E), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x57414B45, id: 8), GetApplicationEventTarget(), 0, &ref8)
        hotKeyRefs.append(ref8)
        var ref5: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x57414B45, id: 5), GetApplicationEventTarget(), 0, &ref5)
        hotKeyRefs.append(ref5)
        for (code, id) in [(UInt32(kVK_UpArrow), UInt32(6)), (UInt32(kVK_DownArrow), UInt32(7))] {
            var r: EventHotKeyRef?
            RegisterEventHotKey(code, UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x57414B45, id: id), GetApplicationEventTarget(), 0, &r)
            hotKeyRefs.append(r)
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
