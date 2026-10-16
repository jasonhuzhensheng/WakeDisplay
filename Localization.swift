// WakeDisplay localization — generated from translations.py, do not edit by hand.
// UI language: "Automatic" follows the macOS preferred language, falling back to English.
import Foundation

enum Lang: String, CaseIterable {
    case auto
    case en = "en"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja = "ja"
    case ko = "ko"
    case es = "es"
    case fr = "fr"
    case de = "de"
    case pt = "pt"
    case it = "it"
    case ru = "ru"
    case ar = "ar"
    case hi = "hi"
    case id = "id"
    case tr = "tr"
    case vi = "vi"
}

let langNativeNames: [Lang: String] = [
    .en: "English",
    .zhHans: "简体中文",
    .zhHant: "繁體中文",
    .ja: "日本語",
    .ko: "한국어",
    .es: "Español",
    .fr: "Français",
    .de: "Deutsch",
    .pt: "Português",
    .it: "Italiano",
    .ru: "Русский",
    .ar: "العربية",
    .hi: "हिन्दी",
    .id: "Bahasa Indonesia",
    .tr: "Türkçe",
    .vi: "Tiếng Việt",
]

/// Stored choice ("auto" when unset, so new users get their system language)
var currentLang: Lang = Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "auto") ?? .auto

/// The language actually used for text: resolves .auto against the system's preferred languages
func effectiveLang() -> Lang {
    if currentLang != .auto { return currentLang }
    for pref in Locale.preferredLanguages {
        let p = pref.lowercased()
        if p.hasPrefix("zh") {
            return (p.contains("hant") || p.hasSuffix("-tw") || p.hasSuffix("-hk") || p.hasSuffix("-mo")) ? .zhHant : .zhHans
        }
        if p.hasPrefix("pt") { return .pt }
        let base = String(p.prefix(2))
        if let l = Lang.allCases.first(where: { $0 != .auto && $0.rawValue == base }) { return l }
    }
    return .en
}

/// L("English text") → text in the current UI language (falls back to English)
func L(_ en: String) -> String {
    let l = effectiveLang()
    if l == .en { return en }
    return translationTable(l)[en] ?? en
}

/// Only the active language's table is ever built (and cached), not all 16 at once
private var cachedTable: (lang: Lang, table: [String: String])?
func translationTable(_ l: Lang) -> [String: String] {
    if let c = cachedTable, c.lang == l { return c.table }
    let t = buildTable(l)
    cachedTable = (l, t)
    return t
}

let hidpiHelpEN = "macOS only generates HiDPI scaling modes for displays with high enough pixel density (usually ≥ 4K).\n1080p / 2K portable monitors typically expose native modes only, so System Settings offers no \"Larger Text\" either.\n\nOptions:\n• Pick a lower non-HiDPI resolution here (e.g. 1600×900): bigger text, slightly soft.\n• For \"big and sharp\", turn on \"Sharp Scaling at Native Resolution\" in this submenu: WakeDisplay renders the desktop on a HiDPI virtual display and mirrors your panel onto it, so the panel keeps its native resolution while text gets larger."
let pmsetMsgEN = "Will run:\nsudo pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0\n\nEffect: USB-C power is no longer cut when the lid is closed or the screen is locked. A laptop on battery will drain faster. Continue?"
let edidMsgEN = "Will delete /Library/Preferences/com.apple.windowserver.displays.plist and the user-level display config, then restart the Mac.\nPersonal data is untouched, but display arrangement / scaling settings will reset. Continue?"
let aboutEN = "macOS menu-bar utility: wake dark USB-C external displays with one click and unlock the HiDPI scaling modes macOS hides.\n\nAuthor: Jason Hu 胡震生 (大老二)\nX: @HUZHENSHENG  ·  0xBig2\n\nBuilt with: Claude Fable 5.1 (Anthropic)\nLicense: MIT"

/// Builds the table for one language from the bundled L10n.bin (decompressed on first use only)
private func buildTable(_ l: Lang) -> [String: String] {
    let index: Int
    switch l {
    case .zhHans: index = 1
    case .zhHant: index = 2
    case .ja: index = 3
    case .ko: index = 4
    case .es: index = 5
    case .fr: index = 6
    case .de: index = 7
    case .pt: index = 8
    case .it: index = 9
    case .ru: index = 10
    case .ar: index = 11
    case .hi: index = 12
    case .id: index = 13
    case .tr: index = 14
    case .vi: index = 15
    default: return [:]
    }
    guard let url = Bundle.main.url(forResource: "L10n", withExtension: "bin"),
          let raw = try? Data(contentsOf: url),
          let plain = try? (raw as NSData).decompressed(using: .zlib) as Data,
          let text = String(data: plain, encoding: .utf8) else { return [:] }
    let recs = text.split(separator: "\u{1E}", omittingEmptySubsequences: false)
    guard recs.count > index else { return [:] }
    let k = recs[0].split(separator: "\u{1F}", omittingEmptySubsequences: false)
    let v = recs[index].split(separator: "\u{1F}", omittingEmptySubsequences: false)
    var t = [String: String](minimumCapacity: k.count)
    for (a, b) in zip(k, v) { t[String(a)] = String(b) }
    return t
}
