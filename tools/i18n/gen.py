import sys
sys.path.insert(0, '.')
from translations import *
def lit(s): return '"' + s.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n') + '"'
special = {"@HIDPI":"hidpiHelpEN","@PMSET":"pmsetMsgEN","@EDID":"edidMsgEN","@ABOUT":"aboutEN"}
for code,(name,arr) in LANGS.items():
    assert len(arr)==len(KEYS), (code,len(arr),len(KEYS))
order = ["en"] + list(LANGS)
case_names = {"en":"en","zh-Hans":"zhHans","zh-Hant":"zhHant"}
cn = lambda c: case_names.get(c, c)
out = []
out.append('''// WakeDisplay localization — generated from translations.py, do not edit by hand.
// UI language: "Automatic" follows the macOS preferred language, falling back to English.
import Foundation

enum Lang: String, CaseIterable {
    case auto''')
for c in order:
    out.append(f'    case {cn(c)} = "{c}"')
out.append('}\n')
names = {"en":"English", **{c:LANGS[c][0] for c in LANGS}}
out.append('let langNativeNames: [Lang: String] = [')
for c in order: out.append(f'    .{cn(c)}: {lit(names[c])},')
out.append(']\n')
out.append('''/// Stored choice ("auto" when unset, so new users get their system language)
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
''')
out.append(f'let hidpiHelpEN = {lit(HIDPI_EN)}')
out.append(f'let pmsetMsgEN = {lit(PMSET_EN)}')
out.append(f'let edidMsgEN = {lit(EDID_EN)}')
out.append(f'let aboutEN = {lit(ABOUT_EN)}\n')
out.append('private func buildTable(_ l: Lang) -> [String: String] {')
out.append('    switch l {')
for c,(name,arr) in LANGS.items():
    out.append(f'    case .{cn(c)}: return [')
    for k,v in zip(KEYS,arr):
        key = special.get(k) or lit(k)
        out.append(f'        {key}: {lit(v)},')
    out.append('    ]')
out.append('    default: return [:]')
out.append('    }')
out.append('}')
open('Localization.swift','w').write('\n'.join(out)+'\n')
print("ok", len(LANGS)+1, "languages,", len(KEYS), "strings")
