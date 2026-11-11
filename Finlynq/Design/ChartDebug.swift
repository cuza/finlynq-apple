import Foundation

/// Counts chart plot builds in Debug builds. With FINLYNQ_CHART_LOG=1 each build writes
/// `FINLYNQ_CHART_PLOT <name> <count>` to stderr, so a run can count rebuilds while the pointer moves.
enum ChartDebug {
    #if DEBUG
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    private static let enabled = ProcessInfo.processInfo.environment["FINLYNQ_CHART_LOG"] == "1"
    #endif

    /// With FINLYNQ_CHART_SWEEP=1, charts that take a pointer sweep their selection across the plot at 120 Hz for
    /// two seconds, two seconds after they appear, the way a pointer moving over the chart would.
    static var sweeps: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["FINLYNQ_CHART_SWEEP"] == "1"
        #else
        false
        #endif
    }

    static func mark(_ text: String) {
        #if DEBUG
        guard enabled else { return }
        FileHandle.standardError.write(Data("FINLYNQ_CHART_MARK \(text)\n".utf8))
        #endif
    }

    static func plotBuilt(_ name: String) {
        #if DEBUG
        guard enabled else { return }
        counts[name, default: 0] += 1
        FileHandle.standardError.write(Data("FINLYNQ_CHART_PLOT \(name) \(counts[name] ?? 0)\n".utf8))
        #endif
    }
}
