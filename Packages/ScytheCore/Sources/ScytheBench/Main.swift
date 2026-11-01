import Foundation

@main
struct ScytheBench {
    static func main() async {
        var arguments = CommandLine.arguments.dropFirst()
        var entryCount = 5000
        var jsonPath: String?
        var baselinePath: String?
        var markdown = false
        var only: String?

        while let argument = arguments.popFirst() {
            switch argument {
            case "--entries": entryCount = arguments.popFirst().flatMap(Int.init) ?? entryCount
            case "--json": jsonPath = arguments.popFirst()
            case "--compare": baselinePath = arguments.popFirst()
            case "--only": only = arguments.popFirst()
            case "--markdown": markdown = true
            case "--seconds": Harness.sampleSeconds = arguments.popFirst().flatMap(Int.init) ?? 2
            default:
                FileHandle.standardError.write(Data("usage: scythe-bench [--entries N] [--only PREFIX] [--json OUT] [--compare BASELINE] [--markdown]\n".utf8))
                exit(2)
            }
        }

        let baseline = baselinePath.flatMap { try? JSONDecoder().decode(Report.self, from: Data(contentsOf: URL(filePath: $0))) }
        if baselinePath != nil, baseline == nil {
            FileHandle.standardError.write(Data("could not read baseline\n".utf8))
            exit(2)
        }

        let data = Dataset.make(entryCount: entryCount)
        var measurements: [Measurement] = []
        for kpi in KPIs.all(data) where only.map({ kpi.id.hasPrefix($0) }) ?? true {
            do {
                measurements.append(try await Harness.measure(kpi))
            } catch {
                FileHandle.standardError.write(Data("\(kpi.id) failed: \(error)\n".utf8))
                exit(1)
            }
        }

        let report = Report(entryCount: data.entries.count, machine: ProcessInfo.processInfo.machineDescription, measurements: measurements)
        if let jsonPath {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(report).write(to: URL(filePath: jsonPath))
        }
        print("Scythe KPIs: \(report.entryCount) entries, \(report.machine)\n")
        print(markdown ? report.markdown(against: baseline) : report.table(against: baseline))
    }
}

private extension ProcessInfo {
    var machineDescription: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let name = String(decoding: brand.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return "\(name), \(operatingSystemVersionString)"
    }
}
