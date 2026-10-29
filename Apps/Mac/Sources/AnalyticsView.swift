import Charts
import ScytheCore
import SwiftUI

struct AnalyticsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HistoryModel.self) private var history
    @Environment(DesktopState.self) private var state

    private enum Granularity: String, CaseIterable, Identifiable {
        case auto = "Auto", day = "Day", week = "Week", month = "Month"
        var id: String { rawValue }
    }

    @State private var granularity: Granularity = .auto

    var body: some View {
        let rows = state.filter.apply(to: history.entries, weekStart: history.weekStart)
        let analytics = EntryAnalytics(rows)
        let format = history.hoursFormat

        ScrollView {
            if history.entries.isEmpty {
                if history.isRefreshing {
                    ProgressView("Loading your history…")
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "chart.bar",
                        description: Text(history.failure ?? "Entries from Harvest appear here once connected.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No matching entries", systemImage: "magnifyingglass")
                } description: {
                    Text("Nothing in your history fits this filter.")
                } actions: {
                    Button("Clear Filter") { state.filter = EntryFilter() }
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    summary(analytics, format: format)
                    trend(analytics, format: format)
                    HStack(alignment: .top, spacing: 16) {
                        card("By project") { BucketChart(buckets: analytics.byProject(), format: format) }
                        card("Billable") { BillableDonut(analytics: analytics, format: format) }
                            .frame(width: 280)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        card("By client") { BucketChart(buckets: analytics.byClient(), format: format) }
                        card("By task") { BucketChart(buckets: analytics.byTask(), format: format) }
                    }
                }
                .padding(16)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                CSVExportButton(rows: rows)
                RefreshButton()
            }
        }
    }

    // MARK: - Sections

    private func summary(_ analytics: EntryAnalytics, format: HoursFormat) -> some View {
        let metrics = [
            StatCard(title: "Total", value: analytics.totalHours.formattedHours(format), symbol: "clock"),
            StatCard(
                title: "Billable",
                value: analytics.billableShare.formatted(.percent.precision(.fractionLength(0))),
                detail: analytics.billableHours.formattedHours(format),
                symbol: "dollarsign.circle"
            ),
            StatCard(title: "Active days", value: analytics.activeDays.formatted(), symbol: "calendar"),
            StatCard(
                title: "Average a day",
                value: analytics.averagePerActiveDay.formattedHours(format),
                symbol: "gauge.medium"
            ),
            StatCard(title: "Entries", value: analytics.entryCount.formatted(), symbol: "list.bullet")
        ]

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(metrics.indices, id: \.self) { index in metrics[index] }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(metrics.indices, id: \.self) { index in metrics[index] }
            }
        }
    }

    private func trend(_ analytics: EntryAnalytics, format: HoursFormat) -> some View {
        let unit = resolvedGranularity(analytics)
        let periods: [PeriodHours]
        let calendarUnit: Calendar.Component
        switch unit {
        case .day, .auto: periods = analytics.byDay(); calendarUnit = .day
        case .week: periods = analytics.byWeek(weekStart: history.weekStart); calendarUnit = .weekOfYear
        case .month: periods = analytics.byMonth(); calendarUnit = .month
        }

        return card("Hours over time") {
            VStack(alignment: .trailing, spacing: 8) {
                Picker("Group by", selection: $granularity) {
                    ForEach(Granularity.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Chart {
                    ForEach(periods) { period in
                        BarMark(
                            x: .value("Period", period.start.startOfDay(), unit: calendarUnit),
                            y: .value("Hours", period.billableHours)
                        )
                        .foregroundStyle(by: .value("Kind", "Billable"))
                        BarMark(
                            x: .value("Period", period.start.startOfDay(), unit: calendarUnit),
                            y: .value("Hours", period.hours - period.billableHours)
                        )
                        .foregroundStyle(by: .value("Kind", "Non-billable"))
                    }
                }
                .chartForegroundStyleScale(["Billable": Color.accentColor, "Non-billable": Color.gray.opacity(0.45)])
                .chartYAxisLabel("Hours")
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: periods)
                .frame(height: 220)
            }
        }
    }

    /// A year of daily bars is unreadable and a week of monthly ones is one bar, so the
    /// automatic choice follows how much time the filter spans.
    private func resolvedGranularity(_ analytics: EntryAnalytics) -> Granularity {
        guard granularity == .auto else { return granularity }
        let dates = analytics.entries.map(\.spentDate)
        guard let first = dates.min(), let last = dates.max() else { return .day }
        switch last.daysSince(first) {
        case ..<45: return .day
        case ..<400: return .week
        default: return .month
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            content()
        } label: {
            Text(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let value: String
    var detail: String?
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: value)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The biggest few buckets as horizontal bars, with the hours at the end of each.
private struct BucketChart: View {
    let buckets: [HoursBucket]
    let format: HoursFormat
    private let limit = 8

    var body: some View {
        let shown = Array(buckets.prefix(limit))
        let longest = max(shown.map(\.hours).max() ?? 1, 1)
        VStack(spacing: 8) {
            ForEach(shown) { bucket in
                HStack(spacing: 10) {
                    Text(bucket.name)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(4, geometry.size.width * bucket.hours / longest))
                    }
                    .frame(height: 10)
                    Text(bucket.hours.formattedHours(format))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(GlassInk.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .help(bucket.detail.map { "\(bucket.name) · \($0)" } ?? bucket.name)
                .accessibilityElement(children: .combine)
            }
        }
        if buckets.count > limit {
            Text("and \((buckets.count - limit).formatted()) more")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
        }
    }
}

private struct BillableDonut: View {
    let analytics: EntryAnalytics
    let format: HoursFormat

    var body: some View {
        let slices = [("Billable", analytics.billableHours), ("Non-billable", analytics.nonBillableHours)]
        VStack(spacing: 10) {
            Chart(slices, id: \.0) { slice in
                SectorMark(angle: .value("Hours", slice.1), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(by: .value("Kind", slice.0))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Billable": Color.accentColor, "Non-billable": Color.gray.opacity(0.45)])
            .chartLegend(.hidden)
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(analytics.billableShare, format: .percent.precision(.fractionLength(0)))
                        .font(.title2.weight(.semibold))
                    Text("billable").font(.caption).foregroundStyle(GlassInk.secondary)
                }
            }
            .frame(height: 160)

            HStack {
                legend("Billable", analytics.billableHours, Color.accentColor)
                Spacer()
                legend("Non-billable", analytics.nonBillableHours, Color.gray.opacity(0.45))
            }
        }
    }

    private func legend(_ name: String, _ hours: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.caption).foregroundStyle(GlassInk.secondary)
                Text(hours.formattedHours(format)).font(.callout).monospacedDigit()
            }
        }
    }
}
