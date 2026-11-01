import Foundation

typealias Operation = @Sendable () async throws -> Void

struct KPI: Sendable {
    let id: String
    let group: String
    let title: String
    let thread: Thread
    let budgetMs: Double
    var iterations = 1
    let prepare: @Sendable () async throws -> Operation

    enum Thread: String, Codable, Sendable { case main, background }
}

struct Measurement: Codable, Sendable {
    var id: String
    var group: String
    var title: String
    var thread: KPI.Thread
    var budgetMs: Double
    var medianMs: Double
    var minMs: Double
    var p95Ms: Double
    var samples: Int
}

final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

enum Harness {
    /// Raised with `--seconds` so a profiler has long enough to sample one operation.
    nonisolated(unsafe) static var sampleSeconds = 2

    static func measure(_ kpi: KPI) async throws -> Measurement {
        let operation = try await kpi.prepare()
        for _ in 0..<3 { try await operation() }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(sampleSeconds)
        var times: [Double] = []
        while times.count < 7 || ((times.count < 30 || sampleSeconds > 2) && clock.now < deadline) {
            let elapsed = try await clock.measure { try await operation() }
            times.append(elapsed.milliseconds / Double(kpi.iterations))
        }
        times.sort()
        return Measurement(
            id: kpi.id, group: kpi.group, title: kpi.title, thread: kpi.thread, budgetMs: kpi.budgetMs,
            medianMs: times[times.count / 2], minMs: times[0],
            p95Ms: times[min(times.count - 1, Int(Double(times.count) * 0.95))],
            samples: times.count
        )
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

func consume<T>(_ value: T) {
    withExtendedLifetime(value) {}
}
