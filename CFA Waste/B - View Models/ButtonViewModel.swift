import SwiftUI
import FirebaseAuth

@MainActor
class ButtonViewModel: ObservableObject {
    @Published var button: ButtonObject
    private let userId: String
    @Published var selectedDate: Date = Date() // Track the selected date

    init(button: ButtonObject) {
        self.button = button
        self.userId = Auth.auth().currentUser?.uid ?? "unknownUser"
    }

    // MARK: - Increment Tally for a Specific Date
    func incrementTally(by amount: Int, date: Date) async {
        let formattedDate = formatDate(date)

        // Prevent negative tally
        guard (button.tallies[formattedDate] ?? 0) + amount >= 0 else { return }

        // Update tally locally for immediate UI feedback
        button.tallies[formattedDate, default: 0] += amount

        // Persist the change (await to preserve ordering in this async context)
        do {
            try await FirebaseService.shared.updateButtonTally(
                buttonId: button.id,
                forUserId: userId,
                tally: button.tallies[formattedDate] ?? 0,
                date: date
            )
        } catch {
            print("Failed to update tally: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete Button
    func deleteButton(completion: @escaping () -> Void) async {
        do {
            try await FirebaseService.shared.deleteButtonObject(button.id, forUserId: userId)
            completion() // Notify parent view to remove this button
        } catch {
            print("Failed to delete button: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Button Order
    func updateOrder(to newOrder: Int) async {
        button.order = newOrder
        do {
            try await FirebaseService.shared.updateButtonOrder(
                buttonId: button.id,
                forUserId: userId,
                order: newOrder
            )
        } catch {
            print("Failed to update order: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Changes
    func saveChanges() async {
        do {
            try await FirebaseService.shared.addButton(button, forUserId: userId)
        } catch {
            print("Failed to save button changes: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Tally for a Specific Date
    func getTally(for date: Date) -> Int {
        return button.tallies[formatDate(date)] ?? 0
    }

    // MARK: - Check if Selected Date is Today
    func isToday(_ date: Date) -> Bool {
        return formatDate(date) == formatDate(Date())
    }

    // MARK: - Date Formatting
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current // use device time as your app expects
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
