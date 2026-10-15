// WakeDisplay widget — desktop / Notification Center buttons (macOS 14+).
// Widgets are sandboxed and can't touch displays, so each button opens a wakedisplay:// URL;
// the WakeDisplay menu-bar app receives it and does the work.
// WakeDisplay 小组件：按钮通过 wakedisplay:// 链接把命令交给菜单栏程序执行。
import WidgetKit
import SwiftUI

// Widget text follows the system language (widgets can't read the app's own setting).
private let wLang: String = {
    let p = (Locale.preferredLanguages.first ?? "en").lowercased()
    if p.hasPrefix("zh") { return (p.contains("hant") || p.hasSuffix("-tw") || p.hasSuffix("-hk") || p.hasSuffix("-mo")) ? "zh-Hant" : "zh-Hans" }
    return String(p.prefix(2))
}()
//                 Wake Display, Tap to wake, Wake, Force Reset, Outdoor, Larger Text, Smaller Text, Menu, description
private let wStrings: [String: [String]] = [
    "zh-Hans": ["唤醒显示器", "点一下唤醒", "唤醒", "强制重置", "户外模式", "字体变大", "字体变小", "菜单", "唤醒显示器、户外模式、字体大小。"],
    "zh-Hant": ["喚醒顯示器", "點一下喚醒", "喚醒", "強制重置", "戶外模式", "放大文字", "縮小文字", "選單", "喚醒顯示器、戶外模式、文字大小。"],
    "ja": ["ディスプレイを起動", "タップで起動", "起動", "強制リセット", "屋外モード", "文字を大きく", "文字を小さく", "メニュー", "ディスプレイ起動、屋外モード、文字サイズ。"],
    "ko": ["디스플레이 깨우기", "탭하여 깨우기", "깨우기", "강제 재설정", "야외 모드", "텍스트 크게", "텍스트 작게", "메뉴", "디스플레이 깨우기, 야외 모드, 텍스트 크기."],
    "es": ["Activar pantalla", "Toca para activar", "Activar", "Reinicio forzado", "Exterior", "Texto más grande", "Texto más pequeño", "Menú", "Activar pantallas, modo exterior y tamaño de texto."],
    "fr": ["Réveiller l’écran", "Touchez pour réveiller", "Réveiller", "Réinit. forcée", "Extérieur", "Texte plus grand", "Texte plus petit", "Menu", "Réveil des écrans, mode extérieur et taille du texte."],
    "de": ["Display aufwecken", "Tippen zum Aufwecken", "Aufwecken", "Reset erzwingen", "Outdoor", "Größerer Text", "Kleinerer Text", "Menü", "Displays aufwecken, Outdoor-Modus und Textgröße."],
    "pt": ["Despertar tela", "Toque para despertar", "Despertar", "Redefinir", "Externo", "Texto maior", "Texto menor", "Menu", "Despertar telas, modo externo e tamanho do texto."],
    "it": ["Riattiva monitor", "Tocca per riattivare", "Riattiva", "Reset forzato", "Esterni", "Testo più grande", "Testo più piccolo", "Menu", "Riattiva monitor, modalità esterni e dimensione testo."],
    "ru": ["Разбудить дисплей", "Нажмите, чтобы разбудить", "Разбудить", "Сброс", "Улица", "Крупнее текст", "Мельче текст", "Меню", "Пробуждение дисплеев, уличный режим и размер текста."],
    "ar": ["إيقاظ الشاشة", "انقر للإيقاظ", "إيقاظ", "إعادة ضبط", "الوضع الخارجي", "نص أكبر", "نص أصغر", "القائمة", "إيقاظ الشاشات والوضع الخارجي وحجم النص."],
    "hi": ["डिस्प्ले जगाएँ", "जगाने के लिए टैप करें", "जगाएँ", "रीसेट", "आउटडोर", "बड़ा टेक्स्ट", "छोटा टेक्स्ट", "मेनू", "डिस्प्ले जगाएँ, आउटडोर मोड और टेक्स्ट आकार।"],
    "id": ["Bangunkan Layar", "Ketuk untuk bangunkan", "Bangunkan", "Reset Paksa", "Luar Ruangan", "Teks Lebih Besar", "Teks Lebih Kecil", "Menu", "Bangunkan layar, mode luar ruangan, dan ukuran teks."],
    "tr": ["Ekranı Uyandır", "Uyandırmak için dokun", "Uyandır", "Zorla Sıfırla", "Dış Mekân", "Büyük Metin", "Küçük Metin", "Menü", "Ekranı uyandırma, dış mekân modu ve metin boyutu."],
    "vi": ["Đánh thức màn hình", "Chạm để đánh thức", "Đánh thức", "Đặt lại", "Ngoài trời", "Chữ lớn hơn", "Chữ nhỏ hơn", "Menu", "Đánh thức màn hình, chế độ ngoài trời và cỡ chữ."],
]
private let wEN = ["Wake Display", "Tap to wake", "Wake", "Force Reset", "Outdoor", "Larger Text", "Smaller Text", "Menu", "Wake displays, outdoor mode and text size."]
private func T(_ i: Int) -> String { (wStrings[wLang] ?? wEN)[i] }

struct WDEntry: TimelineEntry { let date: Date }

struct WDProvider: TimelineProvider {
    func placeholder(in context: Context) -> WDEntry { WDEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WDEntry) -> Void) { completion(WDEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WDEntry>) -> Void) {
        completion(Timeline(entries: [WDEntry(date: .now)], policy: .never))   // static buttons, no refresh needed
    }
}

struct ActionTile: View {
    let title: String
    let symbol: String
    let action: String
    let tint: Color

    var body: some View {
        Link(destination: URL(string: "wakedisplay://\(action)")!) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct WDSmallView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WakeDisplay")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)
            Text(T(0))
                .font(.system(size: 15, weight: .semibold))
            Text(T(1))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "wakedisplay://wake"))
    }
}

struct WDMediumView: View {
    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ActionTile(title: T(2), symbol: "sun.max.fill", action: "wake", tint: .orange)
                ActionTile(title: T(3), symbol: "arrow.triangle.2.circlepath", action: "reset", tint: .blue)
                ActionTile(title: T(4), symbol: "sun.horizon.fill", action: "outdoor", tint: .yellow)
            }
            GridRow {
                ActionTile(title: T(5), symbol: "textformat.size.larger", action: "larger", tint: .green)
                ActionTile(title: T(6), symbol: "textformat.size.smaller", action: "smaller", tint: .teal)
                ActionTile(title: T(7), symbol: "ellipsis.circle", action: "menu", tint: .gray)
            }
        }
    }
}

struct WDView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WDEntry

    var body: some View {
        Group {
            if family == .systemSmall { WDSmallView() } else { WDMediumView() }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct WakeDisplayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WakeDisplayWidget", provider: WDProvider()) { entry in
            WDView(entry: entry)
        }
        .configurationDisplayName("WakeDisplay")
        .description(T(8))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
