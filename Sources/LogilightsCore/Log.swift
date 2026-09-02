import Foundation
import OSLog

/// Central logger. A bundled .app has nowhere to print to, so everything
/// goes through os_log and can be read with:
///
///     log stream --predicate 'subsystem == "io.github.logilights.Logilights"'
///     log show --last 5m --predicate 'subsystem == "io.github.logilights.Logilights"'
public enum Log {
    public static let subsystem = "io.github.logilights.Logilights"

    public static let devices = Logger(subsystem: subsystem, category: "devices")
    public static let lighting = Logger(subsystem: subsystem, category: "lighting")
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
}
