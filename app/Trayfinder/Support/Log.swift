import os

nonisolated enum Log {
  static let subsystem = "io.github.idestis.trayfinder"
  static func make(_ category: String) -> Logger { Logger(subsystem: subsystem, category: category) }
}
