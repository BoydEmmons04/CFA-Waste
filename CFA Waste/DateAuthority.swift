import Foundation

// Single source of truth for "today" and date keys based on the device's *local* day.
enum DateAuthority {
    // Gregorian calendar pinned to the device's current time zone.
    private static var deviceCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current  // Takes the current day from the device and sets it to the current time zone
        return cal  // return adjusted calendar
    }

    // Returns a date key in the format `yyyy-MM-dd` using the device's local day boundary.
    static func deviceDayKey(for date: Date) -> String {
        let cal = deviceCalendar
        let start = cal.startOfDay(for: date)  // Start = start of current day

        let df = DateFormatter()
        df.calendar = cal  // uses a date formatter and passes the device calendar
        df.locale = Locale(identifier: "en_US_POSIX")   // Tells date formatter to use ascii regardless of the device language
        df.timeZone = .current  // Double checks the current time zone
        df.dateFormat = "yyyy-MM-dd"  // Converts the date to the correct format
        return df.string(from: start)  // Returns the string
    }

    /// Convenience: the key for *now* using the device's local day.
    static var todayKey: String { deviceDayKey(for: Date()) }  // Defines the todayKey with the deviceDayKey function

    /// True if `date` falls within the device's local "today" (respects DST, locale TZ).
    static func isDeviceToday(_ date: Date) -> Bool {  // Returns if the passed date is the  today
        deviceCalendar.isDateInToday(date)
    }
}
