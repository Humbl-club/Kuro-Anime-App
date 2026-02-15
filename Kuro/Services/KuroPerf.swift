import Foundation
import OSLog

enum KuroPerf {
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kuro", category: "perf")
    nonisolated static let signposter = OSSignposter(logger: logger)

    struct Interval {
        let state: OSSignpostIntervalState
        let startedAt: CFAbsoluteTime
        let name: StaticString
    }

    nonisolated static func begin(_ name: StaticString) -> Interval {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        return Interval(state: state, startedAt: CFAbsoluteTimeGetCurrent(), name: name)
    }

    nonisolated static func end(_ interval: Interval, message: String? = nil) {
        signposter.endInterval(interval.name, interval.state)
        let ms = (CFAbsoluteTimeGetCurrent() - interval.startedAt) * 1000
        let msText = String(format: "%.1fms", ms)
        if let message, !message.isEmpty {
            logger.info("\(interval.name, privacy: .public) \(msText, privacy: .public) - \(message, privacy: .public)")
        } else {
            logger.info("\(interval.name, privacy: .public) \(msText, privacy: .public)")
        }
    }
}
