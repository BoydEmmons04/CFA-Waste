import Foundation
import Firebase
import FirebaseFirestore

class FirebaseService {
    // Singleton instance
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Date Formatter
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        return FirebaseService.dateFormatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        return formatDate(date) == formatDate(Date())
    }

    // MARK: - Fetch ButtonObjects for a Specific Date
    /// Retrieves buttons and ensures today's tally is initialized.
    func fetchButtonObjects(forUserId userId: String, date: Date) async throws -> [ButtonObject] {
        let userRef = db.collection("users").document(userId)
        let buttonCollection = userRef.collection("buttons")
        let snapshot = try await buttonCollection.order(by: "order").getDocuments()

        let selectedDate = formatDate(date)
        var buttonObjects: [ButtonObject] = []

        for document in snapshot.documents {
            let data = document.data()
            // Read nested map
            let allTallies = data["tallies"] as? [String: Int] ?? [:]
            let nested = allTallies[selectedDate] ?? 0
            // Also read any root-level field named "tallies.<date>"
            let direct = data["tallies.\(selectedDate)"] as? Int ?? 0
            // Use whichever is higher
            let tallyForDate = max(nested, direct)
            let tallies = [ selectedDate: tallyForDate ]

            let button = ButtonObject(
                id: data["id"] as? String ?? document.documentID,
                image: data["image"] as? String ?? "",
                color: data["color"] as? String ?? "",
                name: data["name"] as? String ?? "",
                cost: data["cost"] as? Double ?? 0.0,
                tallies: tallies,
                group: data["group"] as? String ?? "",
                order: data["order"] as? Int ?? 0,
                timestamp: data["timestamp"] as? Timestamp != nil
                    ? (data["timestamp"] as! Timestamp).dateValue()
                    : Date()
            )
            buttonObjects.append(button)
        }
        return buttonObjects
    }

    // MARK: - Add a New ButtonObject
    func addButton(_ button: ButtonObject, forUserId userId: String) async throws {
        let userRef = db.collection("users").document(userId)
        let buttonRef = userRef.collection("buttons").document(button.id)
        let today = formatDate(Date())

        try await buttonRef.setData([
            "id": button.id,
            "image": button.image,
            "color": button.color,
            "name": button.name,
            "cost": button.cost,
            "group": button.group,
            "order": button.order,
            "timestamp": FieldValue.serverTimestamp(),
            "tallies": [today: button.tallies[today] ?? 0]
        ], merge: true)
    }

    // MARK: - Update Button Tally for a Specific Date
    func updateButtonTally(
        buttonId: String,
        forUserId userId: String,
        tally: Int,
        date: Date
    ) async throws {
        let buttonRef = db.collection("users")
            .document(userId)
            .collection("buttons")
            .document(buttonId)
        let formattedDate = formatDate(date)

        // Fetch current server tally for this date
        let snapshot = try await buttonRef.getDocument()
        let data = snapshot.data() ?? [:]

        // Read nested map value
        let nestedMap = data["tallies"] as? [String: Int] ?? [:]
        let nestedValue = nestedMap[formattedDate] ?? 0
        // Read any root-level field "tallies.<date>" (legacy shape)
        let directValue = data["tallies.\(formattedDate)"] as? Int ?? 0
        let serverValue = max(nestedValue, directValue)

        if tally < serverValue {
            // Authoritative DECREMENT: set exact value (clamped >= 0) via transaction
            let clamped = max(0, tally)
            try await db.runTransaction { tx, errorPointer -> Any? in
                do {
                    _ = try tx.getDocument(buttonRef) // ensure the doc exists / obtain current
                    tx.updateData([
                        "tallies.\(formattedDate)": clamped,
                        "timestamp": FieldValue.serverTimestamp()
                    ], forDocument: buttonRef)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } else if tally > serverValue {
            // Increment path: keep previous behavior (only-if-higher)
            try await buttonRef.updateData([
                "tallies.\(formattedDate)": tally,
                "timestamp": FieldValue.serverTimestamp()
            ])
        } else {
            // Equal — no write
        }
    }

    // MARK: - Fetch Recent Tallies for Last `days` Days
    /// Returns a mapping of buttonId to its tallies within the last `days`.
    func fetchRecentArchives(
        forUserId userId: String,
        days: Int = 31
    ) async throws -> [String: [String: Int]] {
        let userRef = db.collection("users").document(userId)
        let buttonCollection = userRef.collection("buttons")
        let snapshot = try await buttonCollection.getDocuments()
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = formatDate(cutoffDate)
        
        var result: [String: [String: Int]] = [:]
        for doc in snapshot.documents {
            let data = doc.data()
            if let tallies = data["tallies"] as? [String: Int] {
                // Filter keys >= cutoffStr (string-comparison works for "yyyy-MM-dd")
                let filtered = tallies.filter { $0.key >= cutoffStr }
                if !filtered.isEmpty {
                    result[doc.documentID] = filtered
                }
            }
        }
        return result
    }

    // MARK: - Update Button Order
    func updateButtonOrder(
        buttonId: String,
        forUserId userId: String,
        order: Int
    ) async throws {
        let buttonRef = db.collection("users")
            .document(userId)
            .collection("buttons")
            .document(buttonId)
        try await buttonRef.updateData(["order": order])
    }

    // MARK: - Delete ButtonObject
    func deleteButtonObject(
        _ buttonId: String,
        forUserId userId: String
    ) async throws {
        let userRef = db.collection("users").document(userId)
        try await userRef
            .collection("buttons")
            .document(buttonId)
            .delete()
    }
}
