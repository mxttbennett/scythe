import Foundation

struct Report: Codable, Sendable {
    var entryCount: Int
    var machine: String
    var measurements: [Measurement]
}

enum Format {
    static func ms(_ value: Double) -> String {
        switch value {
        case ..<0.01: String(format: "%.4f", value)
        case ..<1: String(format: "%.3f", value)
        case ..<100: String(format: "%.2f", value)
        default: String(format: "%.0f", value)
        }
    }

    static func times(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f×", value) : String(format: "%.1f×", value)
    }

    static func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
        let fill = String(repeating: " ", count: max(0, width - text.count))
        return right ? fill + text : text + fill
    }
}

extension Report {
    func geometricSpeedup(over baseline: Report) -> Double? {
        let ratios = measurements.compactMap { current -> Double? in
            guard let before = baseline.measurements.first(where: { $0.id == current.id }) else { return nil }
            return before.medianMs / current.medianMs
        }
        guard !ratios.isEmpty else { return nil }
        return exp(ratios.map(log).reduce(0, +) / Double(ratios.count))
    }

    func budgetsMet() -> (met: Int, total: Int) {
        (measurements.filter { $0.medianMs <= $0.budgetMs }.count, measurements.count)
    }

    func table(against baseline: Report?) -> String {
        var lines: [String] = []
        let idWidth = (measurements.map(\.id.count).max() ?? 0) + 4
        var header = Format.pad("KPI", idWidth) + Format.pad("thread", 12) + Format.pad("budget", 9, right: true)
        if baseline != nil { header += Format.pad("before", 10, right: true) }
        header += Format.pad(baseline == nil ? "median ms" : "after", 11, right: true)
        if baseline != nil { header += Format.pad("speedup", 10, right: true) }
        header += "  status"
        lines.append(header)
        lines.append(String(repeating: "-", count: header.count))

        var group = ""
        for item in measurements {
            if item.group != group {
                group = item.group
                lines.append(group.uppercased())
            }
            var row = Format.pad("  " + item.id, idWidth) + Format.pad(item.thread.rawValue, 12)
            row += Format.pad(Format.ms(item.budgetMs), 9, right: true)
            if let before = baseline?.measurements.first(where: { $0.id == item.id }) {
                row += Format.pad(Format.ms(before.medianMs), 10, right: true)
                row += Format.pad(Format.ms(item.medianMs), 11, right: true)
                row += Format.pad(Format.times(before.medianMs / item.medianMs), 10, right: true)
            } else {
                if baseline != nil { row += Format.pad("-", 10, right: true) }
                row += Format.pad(Format.ms(item.medianMs), 11, right: true)
                if baseline != nil { row += Format.pad("-", 10, right: true) }
            }
            row += item.medianMs <= item.budgetMs ? "  ok" : "  OVER BUDGET"
            lines.append(row)
        }

        let (met, total) = budgetsMet()
        lines.append("")
        lines.append("Within budget: \(met) of \(total)")
        if let baseline, let speedup = geometricSpeedup(over: baseline) {
            let before = baseline.budgetsMet()
            lines.append("Before:        \(before.met) of \(before.total)")
            lines.append("Snappiness index (geometric mean speedup): \(Format.times(speedup))")
        }
        return lines.joined(separator: "\n")
    }

    func markdown(against baseline: Report?) -> String {
        var lines = [
            baseline == nil
                ? "| KPI | Thread | Budget (ms) | Median (ms) | Status |\n|---|---|---:|---:|---|"
                : "| KPI | Thread | Budget (ms) | Before (ms) | After (ms) | Speedup | Status |\n|---|---|---:|---:|---:|---:|---|"
        ]
        for item in measurements {
            let status = item.medianMs <= item.budgetMs ? "ok" : "over budget"
            if let before = baseline?.measurements.first(where: { $0.id == item.id }) {
                lines.append("| \(item.title) (`\(item.id)`) | \(item.thread.rawValue) | \(Format.ms(item.budgetMs)) | \(Format.ms(before.medianMs)) | \(Format.ms(item.medianMs)) | \(Format.times(before.medianMs / item.medianMs)) | \(status) |")
            } else {
                lines.append("| \(item.title) (`\(item.id)`) | \(item.thread.rawValue) | \(Format.ms(item.budgetMs)) | \(Format.ms(item.medianMs)) | \(status) |")
            }
        }
        return lines.joined(separator: "\n")
    }
}
