import Foundation
import SwiftUI

struct ButtonObject: Identifiable, Codable, Hashable {
    let id: String
    var image: String
    var color: String
    var name: String
    var cost: Double
    var tallies: [String: Int] // Stores tally values per date (keyed by "yyyy-MM-dd")
    var group: String
    var order: Int // Used for ordering buttons
    var timestamp: Date // Creation or last-modified timestamp

    // MARK: - Initializer
    init(
        id: String = UUID().uuidString,
        image: String = "",
        color: String = "#FFFFFF",
        name: String,
        cost: Double,
        tallies: [String: Int] = [:],
        group: String,
        order: Int,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.image = image
        self.color = color
        self.name = name
        self.cost = cost
        self.tallies = tallies
        self.group = group
        self.order = order
        self.timestamp = timestamp
    }

    // MARK: - Tally Accessors
    func tally(for date: String) -> Int {
        return tallies[date] ?? 0
    }

    func totalCost(for date: String) -> Double {
        return cost * Double(tally(for: date))
    }

    // MARK: - Today's Tally & Cost
    var todayTally: Int {
        tally(for: Self.currentDate)
    }

    var todayTotalCost: Double {
        totalCost(for: Self.currentDate)
    }

    // MARK: - SwiftUI Color Conversion
    var uiColor: Color {
        Color(hex: color) ?? .gray
    }

    // MARK: - Date Formatter
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var currentDate: String {
        dateFormatter.string(from: Date())
    }
}

// MARK: - Extension for Converting Hex Colors to SwiftUI Colors
extension Color {
    init?(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgb) else { return nil }
        let red   = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8)  & 0xFF) / 255.0
        let blue  = Double(rgb         & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
