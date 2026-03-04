import Foundation

struct AppSettings: Codable, Hashable {
    // Minutes from midnight local time. Default 3:00 AM.
    var cutoffMinutes: Int = 180

    var cutoffHour: Int { cutoffMinutes / 60 }
    var cutoffMinute: Int { cutoffMinutes % 60 }

    var cutoffDateComponents: DateComponents {
        DateComponents(hour: cutoffHour, minute: cutoffMinute)
    }
}
