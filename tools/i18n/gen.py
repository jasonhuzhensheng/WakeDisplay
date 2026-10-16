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
# Translations live in a compressed resource (L10n.bin, raw DEFLATE), not in the binary.
# Layout (UTF-8): record 0 = English keys, then one record per language in Lang order;
# records separated by U+001E, strings inside a record by U+001F.
import zlib
US, RS = "\u001f", "\u001e"
eng = {"@HIDPI":HIDPI_EN,"@PMSET":PMSET_EN,"@EDID":EDID_EN,"@ABOUT":ABOUT_EN}
records = [US.join(eng.get(k,k) for k in KEYS)]
for code,(name,arr) in LANGS.items():
    for v in arr: assert US not in v and RS not in v
    records.append(US.join(arr))
c = zlib.compressobj(9, zlib.DEFLATED, -15)
data = c.compress(RS.join(records).encode()) + c.flush()
open('L10n.bin','wb').write(data)
idx = {c:i+1 for i,c in enumerate(LANGS)}
out.append('/// Builds the table for one language from the bundled L10n.bin (decompressed on first use only)')
out.append('private func buildTable(_ l: Lang) -> [String: String] {')
out.append('    let index: Int')
out.append('    switch l {')
for c in LANGS:
    out.append(f'    case .{cn(c)}: index = {idx[c]}')
out.append('    default: return [:]')
out.append('    }')
out.append('    guard let url = Bundle.main.url(forResource: "L10n", withExtension: "bin"),')
out.append('          let raw = try? Data(contentsOf: url),')
out.append('          let plain = try? (raw as NSData).decompressed(using: .zlib) as Data,')
out.append('          let text = String(data: plain, encoding: .utf8) else { return [:] }')
out.append('    let recs = text.split(separator: "\\u{1E}", omittingEmptySubsequences: false)')
out.append('    guard recs.count > index else { return [:] }')
out.append('    let k = recs[0].split(separator: "\\u{1F}", omittingEmptySubsequences: false)')
out.append('    let v = recs[index].split(separator: "\\u{1F}", omittingEmptySubsequences: false)')
out.append('    var t = [String: String](minimumCapacity: k.count)')
out.append('    for (a, b) in zip(k, v) { t[String(a)] = String(b) }')
out.append('    return t')
out.append('}')
open('Localization.swift','w').write('\n'.join(out)+'\n')
print("ok", len(LANGS)+1, "languages,", len(KEYS), "strings; L10n.bin", len(data), "bytes")
