// Quiet hours, picked in the menu: the hours of the Mac's clock in which reports from other threads
// are not spoken but kept for the morning briefing. quiet_hours.py holds the same rules for the
// scripts. The setting is the file "quiet-hours" next to the app: "23 12" (from 23:00 until
// 12:00), or "off 23 12" when turned off. No file, or one that cannot be read, means 23:00 to 12:00.

import Foundation

struct QuietHours: Equatable {
    static let standard = QuietHours(on: true, start: 23, end: 12)
    static let hoursInDay = 24

    let on: Bool
    let start: Int
    let end: Int

    static func parse(_ text: String) -> QuietHours {
        var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let on = words.first != "off"
        if !on { words.removeFirst() }
        guard words.count == 2, let start = Int(words[0]), let end = Int(words[1]),
              (0..<hoursInDay).contains(start), (0..<hoursInDay).contains(end) else { return standard }
        return QuietHours(on: on, start: start, end: end)
    }

    var text: String { "\(on ? "" : "off ")\(start) \(end)\n" }

    /// "23:00–12:00", the hours whether or not they are on.
    var span: String { "\(QuietHours.clock(start))–\(QuietHours.clock(end))" }

    static func clock(_ hour: Int) -> String { String(format: "%02d:00", hour) }

    func with(on: Bool? = nil, start: Int? = nil, end: Int? = nil) -> QuietHours {
        QuietHours(on: on ?? self.on, start: start ?? self.start, end: end ?? self.end)
    }
}

func quietHoursFile(base: URL) -> URL { base.appendingPathComponent("quiet-hours") }

func savedQuietHours(base: URL) -> QuietHours {
    guard let text = try? String(contentsOf: quietHoursFile(base: base), encoding: .utf8) else { return .standard }
    return QuietHours.parse(text)
}

/// Written whole, then moved into place, so a script never reads half a line.
func saveQuietHours(_ hours: QuietHours, base: URL) {
    do {
        try hours.text.write(to: quietHoursFile(base: base), atomically: true, encoding: .utf8)
    } catch {
        NSLog("avatar: cannot save the quiet hours: \(error.localizedDescription)")
    }
}
