import ScytheCore
import SwiftUI

/// Where the visible day went, project by project. Read-only: a click here must never start a timer.
struct DayBreakdown: View {
    @Environment(\.uiScale) private var uiScale

    let buckets: [HoursBucket]
    let format: HoursFormat

    private var total: Double { buckets.reduce(0) { $0 + $1.hours } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * uiScale) {
            Text("By project")
                .uiFont(.caption)
                .foregroundStyle(.secondary)
                .uiPadding(.horizontal, 10)
            SizedScrollView(maxHeight: 5 * 40 * uiScale) {
                LazyVStack(alignment: .leading, spacing: 6 * uiScale) {
                    ForEach(buckets) { bucket in
                        row(bucket)
                    }
                }
            }
        }
    }

    private func row(_ bucket: HoursBucket) -> some View {
        VStack(alignment: .leading, spacing: 3 * uiScale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * uiScale) {
                VStack(alignment: .leading, spacing: 1 * uiScale) {
                    Text(bucket.name)
                        .uiFont(.callout)
                        .lineLimit(1)
                    if let client = bucket.detail, !client.isEmpty {
                        Text(client)
                            .uiFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(bucket.hours.formattedHours(format))
                    .uiFont(.callout, monospacedDigit: true)
            }
            shareBar(total > 0 ? bucket.hours / total : 0)
        }
        .uiPadding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    private func shareBar(_ fraction: Double) -> some View {
        Capsule()
            .fill(.quaternary)
            .uiFrame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * fraction)
                }
            }
    }
}
