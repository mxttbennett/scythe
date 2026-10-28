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
                .foregroundStyle(GlassInk.secondary)
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
                    DotLabel(name: bucket.name, kind: .project)
                        .uiFont(.callout)
                    if let client = bucket.detail, !client.isEmpty {
                        DotLabel(name: client, kind: .client)
                            .uiFont(.caption)
                            .foregroundStyle(GlassInk.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1 * uiScale) {
                    Text(bucket.hours.formattedHours(format))
                        .uiFont(.callout, monospacedDigit: true)
                    Text((total > 0 ? bucket.hours / total : 0).formatted(.percent.precision(.fractionLength(0))))
                        .uiFont(.caption)
                        .foregroundStyle(GlassInk.secondary)
                }
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
