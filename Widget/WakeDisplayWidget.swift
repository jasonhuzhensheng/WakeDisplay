// WakeDisplay widget — desktop / Notification Center buttons (macOS 14+).
// Widgets are sandboxed and can't touch displays, so each button opens a wakedisplay:// URL;
// the WakeDisplay menu-bar app receives it and does the work.
// WakeDisplay 小组件：按钮通过 wakedisplay:// 链接把命令交给菜单栏程序执行。
import WidgetKit
import SwiftUI

private let zh = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
private func T(_ en: String, _ cn: String) -> String { zh ? cn : en }

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
            Text(T("Wake Display", "唤醒显示器"))
                .font(.system(size: 15, weight: .semibold))
            Text(T("Tap to wake", "点一下唤醒"))
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
                ActionTile(title: T("Wake", "唤醒"), symbol: "sun.max.fill", action: "wake", tint: .orange)
                ActionTile(title: T("Force Reset", "强制重置"), symbol: "arrow.triangle.2.circlepath", action: "reset", tint: .blue)
                ActionTile(title: T("Outdoor", "户外模式"), symbol: "sun.horizon.fill", action: "outdoor", tint: .yellow)
            }
            GridRow {
                ActionTile(title: T("Larger Text", "字体变大"), symbol: "textformat.size.larger", action: "larger", tint: .green)
                ActionTile(title: T("Smaller Text", "字体变小"), symbol: "textformat.size.smaller", action: "smaller", tint: .teal)
                ActionTile(title: T("Menu", "菜单"), symbol: "ellipsis.circle", action: "menu", tint: .gray)
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
        .description(T("Wake displays, outdoor mode and text size.", "唤醒显示器、户外模式、字体大小。"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
