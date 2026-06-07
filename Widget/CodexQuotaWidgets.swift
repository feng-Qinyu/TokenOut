import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), snapshot: QuotaStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let entry = QuotaEntry(date: Date(), snapshot: QuotaStore.load() ?? .placeholder)
        let next = Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TokenOutWidgetView: View {
    let entry: QuotaEntry

    var body: some View {
        QuotaRingsView(snapshot: entry.snapshot)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.27, blue: 0.30).opacity(0.68),
                        Color(red: 0.06, green: 0.14, blue: 0.17).opacity(0.52)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

@main
struct TokenOutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenOutWidget", provider: QuotaProvider()) { entry in
            TokenOutWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenOut")
        .description("查看本周、5小时和今日 Token 余量。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
