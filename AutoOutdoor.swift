// Copyright (c) 2026 Jason Hu (胡震生) — MIT License. The WakeDisplay name and logo are not covered, see TRADEMARKS.md
// Auto Outdoor Mode: read the MacBook's ambient light sensor and switch Outdoor Mode on in bright
// light, off again indoors. Apple Silicon has no public ALS API; this uses the private
// IOHIDEventSystemClient interface (same approach as Lunar). If it is unavailable, the feature
// simply reports "Light sensor not available".
// 自动户外模式：读取环境光传感器，强光下自动开启户外模式，回到室内自动关闭。
import Cocoa

// MARK: - Ambient light sensor (private IOKit HID event system)

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

enum LightSensor {
    private static let kTypeALS: Int64 = 12                       // kIOHIDEventTypeAmbientLightSensor
    private static let kFieldLevel: Int32 = Int32(12 << 16)       // kIOHIDEventFieldAmbientLightSensorLevel

    // The client owns its services: keep both alive for the app's lifetime (releasing the client
    // early leaves the service dangling and crashes on the next read).
    private static let client: CFTypeRef? = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
    private static let service: CFTypeRef? = {
        guard let client else { return nil }
        // Apple vendor page 0xFF00, usage 4 = ambient light sensor
        let match = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, match)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef],
              let first = services.first else { return nil }
        return first
    }()

    static var available: Bool { lux() != nil }

    /// Current illuminance in lux, or nil when the sensor can't be read
    static func lux() -> Double? {
        guard let s = service,
              let ev = IOHIDServiceClientCopyEvent(s, kTypeALS, 0, 0)?.takeRetainedValue() else { return nil }
        let v = IOHIDEventGetFloatValue(ev, kFieldLevel)
        return v.isFinite && v >= 0 ? v : nil
    }
}

// MARK: - Auto Outdoor Mode

enum AutoOutdoor {
    enum Sensitivity: String, CaseIterable {
        case low, medium, high
        /// lux needed (for ~10 s) to switch on; off below 40 % of it (for ~30 s)
        var onLux: Double { switch self { case .low: return 10_000; case .medium: return 5_000; case .high: return 2_500 } }
        var offLux: Double { onLux * 0.4 }
        var title: String { switch self { case .low: return L("Low"); case .medium: return L("Medium"); case .high: return L("High") } }
    }

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoOutdoor") }       // off by default
        set { UserDefaults.standard.set(newValue, forKey: "autoOutdoor"); newValue ? start() : stop() }
    }
    static var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: UserDefaults.standard.string(forKey: "autoOutdoorSensitivity") ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "autoOutdoorSensitivity") }
    }

    private(set) static var lastLux: Double?
    private static var timer: Timer?
    private static var brightSeconds = 0, darkSeconds = 0
    private static var turnedOnByUs = false     // only auto-off what we auto-on'd
    private static var suppressed = false       // user switched it off in bright light → wait for darkness

    static func start() {
        guard timer == nil else { return }
        brightSeconds = 0; darkSeconds = 0
        timer = every(2, tolerance: 0.5) { tick() }   // sample every 2 s; counters below are in seconds
    }
    static func stop() { timer?.invalidate(); timer = nil }

    /// Called whenever the user toggles Outdoor Mode by hand
    static func manualToggled(isOnNow: Bool) {
        turnedOnByUs = false
        if !isOnNow, let l = lastLux, l >= sensitivity.offLux { suppressed = true }
    }

    private static func tick() {
        guard let lux = LightSensor.lux() else { return }
        lastLux = lux
        let s = sensitivity
        if lux >= s.onLux { brightSeconds += 2; darkSeconds = 0 }
        else if lux < s.offLux { darkSeconds += 2; brightSeconds = 0 }
        else { brightSeconds = 0; darkSeconds = 0 }

        if darkSeconds >= 30 { suppressed = false }

        if !outdoor.isOn, !suppressed, brightSeconds >= 10 {
            outdoor.start()
            (NSApp.delegate as? AppDelegate)?.updateIcon()
            turnedOnByUs = true
            brightSeconds = 0
            WakeReminder.show("☀️ " + L("Outdoor Mode is on"), L("Turned on automatically: bright light detected"))
            Telemetry.feature("autoOutdoorOn", source: "sensor")
        } else if outdoor.isOn, turnedOnByUs, darkSeconds >= 30 {
            outdoor.stop()
            (NSApp.delegate as? AppDelegate)?.updateIcon()
            turnedOnByUs = false
            darkSeconds = 0
            WakeReminder.show(L("Outdoor Mode is off"), L("Turned off automatically: back indoors"))
        }
    }

    // MARK: menu (lives in ⚙️ Advanced)

    static func menuItem() -> NSMenuItem {
        let target = AutoOutdoorMenuTarget.shared
        let sub = NSMenu(); sub.autoenablesItems = false

        let toggle = NSMenuItem(title: L("Auto Outdoor Mode (light sensor)"), action: #selector(AutoOutdoorMenuTarget.toggle), keyEquivalent: "")
        toggle.target = target; toggle.state = enabled ? .on : .off
        sub.addItem(toggle)

        // Only read the (private-API) sensor when the feature is on, so the default path never touches it
        if enabled {
            let reading: String
            if let l = lastLux ?? LightSensor.lux() { reading = L("Ambient light: ") + "\(Int(l.rounded()).formatted()) lux" }
            else { reading = L("Light sensor not available") }
            let r = NSMenuItem(title: reading, action: nil, keyEquivalent: ""); r.isEnabled = false
            sub.addItem(r)
        }
        sub.addItem(.separator())

        let head = NSMenuItem(title: L("Sensitivity"), action: nil, keyEquivalent: ""); head.isEnabled = false
        sub.addItem(head)
        for s in Sensitivity.allCases {
            let i = NSMenuItem(title: "\(s.title)  (≥ \(Int(s.onLux).formatted()) lux)", action: #selector(AutoOutdoorMenuTarget.setSensitivity(_:)), keyEquivalent: "")
            i.target = target; i.representedObject = s.rawValue; i.state = sensitivity == s ? .on : .off
            sub.addItem(i)
        }
        let p = NSMenuItem(title: "🌤 " + L("Auto Outdoor Mode (light sensor)"), action: nil, keyEquivalent: "")
        p.submenu = sub
        return p
    }
}

final class AutoOutdoorMenuTarget: NSObject {
    static let shared = AutoOutdoorMenuTarget()
    @objc func toggle() {
        AutoOutdoor.enabled.toggle()
        if AutoOutdoor.enabled { Telemetry.feature("autoOutdoor") }
    }
    @objc func setSensitivity(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let v = AutoOutdoor.Sensitivity(rawValue: raw) { AutoOutdoor.sensitivity = v }
    }
}
