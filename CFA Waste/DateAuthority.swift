import Foundation

/// Single source of truth for "today" and date keys based on the device's *local* day.
/// Use these helpers anywhere you need to decide if a date is today or build a
/// Firestore key like "yyyy-MM-dd" that should reflect the device's current day
/// regardless of UTC.
enum DateAuthority {
    /// Gregorian calendar pinned to the device's current time zone.
    private static var deviceCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    /// Returns a date key in the format `yyyy-MM-dd` using the device's local day boundary.
    static func deviceDayKey(for date: Date) -> String {
        let cal = deviceCalendar
        let start = cal.startOfDay(for: date)

        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: start)
    }

    /// Convenience: the key for *now* using the device's local day.
    static var todayKey: String { deviceDayKey(for: Date()) }

    /// True if `date` falls within the device's local "today" (respects DST, locale TZ).
    static func isDeviceToday(_ date: Date) -> Bool {
        deviceCalendar.isDateInToday(date)
    }
}
