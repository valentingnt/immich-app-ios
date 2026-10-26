import Foundation
import SQLiteData

/// Dates as Drift stores them with `storeDateTimeAsText`: ISO 8601 with a `T` separator and a `Z`/offset suffix
/// (`2026-10-20T12:25:33.973Z`), or SQLite's `CURRENT_TIMESTAMP` default (`2026-10-20 12:25:33`, UTC).
/// SQLiteData's default `Date` decoding only accepts the latter.
struct DriftDate: QueryRepresentable, QueryBindable, QueryDecodable {
  var queryOutput: Date

  init(queryOutput: Date) {
    self.queryOutput = queryOutput
  }

  init(decoder: inout some QueryDecoder) throws {
    let text = try String(decoder: &decoder)
    guard let date = Self.parse(text) else { throw InvalidDate(text: text) }
    queryOutput = date
  }

  var queryBinding: QueryBinding {
    .text(queryOutput.formatted(Self.formats[0]))
  }

  static func parse(_ text: String) -> Date? {
    for format in formats {
      if let date = try? Date(text, strategy: format) { return date }
    }
    return nil
  }

  private static let formats: [Date.ISO8601FormatStyle] = [
    .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted),
    .iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted),
    .iso8601.year().month().day().dateTimeSeparator(.space).time(includingFractionalSeconds: true),
    .iso8601.year().month().day().dateTimeSeparator(.space).time(includingFractionalSeconds: false),
  ]

  struct InvalidDate: Error {
    let text: String
  }
}

extension DriftDate: SQLiteType {
  static var typeAffinity: SQLiteTypeAffinity { String.typeAffinity }
}
