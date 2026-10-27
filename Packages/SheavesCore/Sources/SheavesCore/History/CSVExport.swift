import Foundation

public enum CSVExport {
    public static let header = "Date,Client,Project,Task,Notes,Hours,Billable"

    public static func entries(_ entries: [TrackedEntry], asOf now: Date = Date()) -> String {
        var lines = [header]
        for entry in entries {
            lines.append([
                entry.spentDate.description,
                entry.client?.name ?? "",
                entry.project.name,
                entry.task.name,
                entry.notes ?? "",
                hours(entry.hours(asOf: now)),
                entry.isBillable ? "yes" : "no",
            ].map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A file for other programs, so the decimal point is fixed rather than the reader's.
    private static func hours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")).grouping(.never))
    }

    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
