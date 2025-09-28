import SwiftUI
import FirebaseAuth
import Combine
import FirebaseFirestore

@MainActor
class ButtonGridViewModel: ObservableObject {
    
    @Published var buttons: [ButtonObject] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedDate: Date = Date() // Store the selected date

    // Pending local tally updates to flush later
    @Published var pendingSyncs: [String: Int] = [:]

    private var previousDate: Date = Date()
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    private var didHydrateToday: Bool = false
    
    // Tracks the currently bound group/date so we can refresh intelligently
    private var currentGroupId: String = ""
    private var currentDateKey: String = ""

    private let userId: String

    // Initialize with the current user's ID
    init() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.userId = "unknownUser"
            return
        }
        self.userId = userId

        // Subscribe to selectedDate changes
        $selectedDate
            .removeDuplicates()
            .sink { [weak self] newDate in
                Task { await self?.handleDateChange(newDate) }
            }
            .store(in: &cancellables)
    }

    /// Bind the grid to a selected group & date. Call from the view onAppear and when either value changes.
    /// This keeps network work minimal by only fetching when the group or day key changes, or if we have no data.
    func bind(groupId: String, date: Date) {
        let key = DateAuthority.deviceDayKey(for: date)
        let changed = buttons.isEmpty || groupId != currentGroupId || key != currentDateKey

        // Track selection
        currentGroupId = groupId
        currentDateKey = key
        if DateAuthority.deviceDayKey(for: selectedDate) != key {
            selectedDate = date
        }

        guard changed else { return }

        // 1) Eagerly fetch snapshot to hydrate UI before user taps
        Task { [weak self] in
            guard let self = self else { return }
            await self.fetchButtons(for: date)

            // 2) Then attach live listeners for subsequent updates
            FirebaseService.shared.stopButtons()

            FirebaseService.shared.listenButtons(storeId: self.userId, groupId: groupId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let items):
                        self.applySnapshot(items, for: self.selectedDate)
                    case .failure(let err):
                        self.errorMessage = "Buttons listen error: \(err.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Update Tally in Firestore for a Specific Date
    func updateTallyInFirestore(for button: ButtonObject, tally: Int, date: Date) async throws {
        guard let index = buttons.firstIndex(where: { $0.id == button.id }) else { return }

        let key = DateAuthority.deviceDayKey(for: date)
        let clamped = max(0, tally)

        let docRef = db
            .collection("users")
            .document(userId)
            .collection("buttons")
            .document(button.id)

        // Read current server value to decide path
        let snapshot = try await docRef.getDocument()
        let data = snapshot.data() ?? [:]
        let serverMap = data["tallies"] as? [String: Int] ?? [:]
        let serverNested = serverMap[key] ?? 0
        let serverDirect = data["tallies.\(key)"] as? Int ?? 0
        let serverValue = max(serverNested, serverDirect)

        if clamped < serverValue {
            // Authoritative DECREMENT: set exact lower value via transaction
            try await db.runTransaction { tx, errorPointer -> Any? in
                do {
                    _ = try tx.getDocument(docRef)
                    tx.setData(["tallies.\(key)": clamped], forDocument: docRef, merge: true)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } else if clamped > serverValue {
            // Increment path: only-if-higher
            try await docRef.setData(["tallies.\(key)": clamped], merge: true)
        } else {
            // Equal — no-op
        }

        // Update local state to reflect the requested tally
        buttons[index].tallies[key] = clamped
        self.objectWillChange.send()
    }

    // MARK: - Increment Tally for a Specific Date
    func incrementTally(for button: ButtonObject, by amount: Int = 1, date: Date) async {
        // Only allow changes for today
        guard DateAuthority.isDeviceToday(date) else { return }
        guard let index = buttons.firstIndex(where: { $0.id == button.id }) else { return }

        let key = DateAuthority.deviceDayKey(for: date)
        let current = buttons[index].tallies[key] ?? 0
        let nextUnclamped = current + amount
        let next = max(0, nextUnclamped) // never negative

        // No-op if nothing changes
        guard next != current else { return }

        // Update locally for immediate UI feedback
        buttons[index].tallies[key] = next
        self.objectWillChange.send()

        if amount < 0 {
            let pendingKey = "\(button.id)|\(key)"
            pendingSyncs.removeValue(forKey: pendingKey)
            // AUTHORITATIVE WRITE for decrements: set exact value on server (clamped >= 0)
            let userDoc = db.collection("users").document(userId)
            let docRef = userDoc.collection("buttons").document(button.id)
            do {
                try await db.runTransaction { tx, errorPointer -> Any? in
                    do {
                        _ = try tx.getDocument(docRef) // ensure doc exists
                        tx.setData(["tallies.\(key)": next], forDocument: docRef, merge: true)
                        return nil
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }
            } catch {
                let ns = error as NSError
                // If we're offline or the backend is temporarily unavailable, keep the local decrement
                // and queue a normal write that will sync when connectivity returns.
                if ns.domain == FirestoreErrorDomain &&
                    (ns.code == FirestoreErrorCode.unavailable.rawValue ||
                     ns.code == FirestoreErrorCode.deadlineExceeded.rawValue ||
                     ns.code == FirestoreErrorCode.internal.rawValue) {

                    do {
                        try await docRef.setData(["tallies.\(key)": next], merge: true)
                        // Local value was already updated above; nothing else to do.
                    } catch {
                        // If even queuing fails, revert locally and report.
                        await MainActor.run {
                            self.buttons[index].tallies[key] = current
                            self.errorMessage = "Queued decrement failed: \(error.localizedDescription)"
                            self.objectWillChange.send()
                        }
                    }
                } else {
                    // Real failure: revert local change and show error
                    await MainActor.run {
                        self.buttons[index].tallies[key] = current
                        self.errorMessage = "Decrement failed: \(error.localizedDescription)"
                        self.objectWillChange.send()
                    }
                }
            }
            return
        }

        // For increments (amount >= 0): keep existing queued-max behavior
        let pendingKey = "\(button.id)|\(key)"
        pendingSyncs[pendingKey] = max(pendingSyncs[pendingKey] ?? 0, next)

        Task.detached { [weak self] in
            await self?.flushPendingSyncs()
        }
    }

    // MARK: - Fetch Buttons for a Specific Date
    func fetchButtons(for date: Date) async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await FirebaseService.shared.fetchButtonObjects(forUserId: userId, date: date)

            if DateAuthority.isDeviceToday(date) {
                let key = DateAuthority.deviceDayKey(for: date)
                let existing = Dictionary(uniqueKeysWithValues: self.buttons.map { ($0.id, $0.tallies[key] ?? 0) })
                let pending = self.pendingSyncs // snapshot of pending queued increments

                let merged: [ButtonObject] = fetched.map { btn in
                    var b = btn
                    let local = existing[btn.id] ?? 0
                    let server = btn.tallies[key] ?? 0
                    let pendingKey = "\(btn.id)|\(key)"

                    if pending[pendingKey] != nil {
                        // There is a pending local increment for this key: prefer the higher value to avoid flicker
                        b.tallies[key] = max(local, server)
                    } else {
                        // No pending increment: prefer server (so authoritative decrements show immediately)
                        b.tallies[key] = server
                    }
                    return b
                }
                self.buttons = merged
                // After merging today's snapshot, drop any queued increments that would override a newer server decrement
                let keysToRemove: [String] = merged.compactMap { btn in
                    let serverVal = btn.tallies[key] ?? 0
                    let pKey = "\(btn.id)|\(key)"
                    if let queued = self.pendingSyncs[pKey], serverVal < queued {
                        return pKey
                    }
                    return nil
                }
                for k in keysToRemove { self.pendingSyncs.removeValue(forKey: k) }
                self.didHydrateToday = true
            } else {
                // Non-today: trust fetched snapshot as-is
                self.buttons = fetched
                self.didHydrateToday = false
            }

            self.sortButtons()
        } catch {
            self.errorMessage = "Failed to fetch buttons: \(error.localizedDescription)"
        }
        isLoading = false
    }


    /// Flushes pending tallies to Firestore, reconciling with the server
    func flushPendingSyncs() async {
        guard !pendingSyncs.isEmpty else { return }
        let db = Firestore.firestore()
        let userDoc = db.collection("users").document(userId)
        let toSync = pendingSyncs
        for (key, localValue) in toSync {
            // If this key was removed after we snapshotted (e.g., due to an authoritative decrement), skip it
            guard self.pendingSyncs[key] != nil else { continue }

            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let buttonId = parts[0]
            let dateKey = parts[1]
            let docRef = userDoc.collection("buttons").document(buttonId)
            do {
                let snapshot = try await docRef.getDocument()
                let serverData = snapshot.data() ?? [:]
                let serverMap = serverData["tallies"] as? [String: Int] ?? [:]
                let serverNested = serverMap[dateKey] ?? 0
                let serverDirect = serverData["tallies.\(dateKey)"] as? Int ?? 0
                let serverValue = max(serverNested, serverDirect)

                // Only push when our pending local value is actually higher than server (increment case)
                if localValue > serverValue {
                    try await docRef.setData(["tallies.\(dateKey)": localValue], merge: true)
                }

                // Remove from pending only on success (or no-op if server already higher/equal)
                await MainActor.run {
                    self.pendingSyncs.removeValue(forKey: key)
                }
            } catch {
                print("⚠️ Failed to sync \(buttonId) @ \(dateKey): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Add Button
    func addButton(_ button: ButtonObject) async {
        do {
            try await FirebaseService.shared.addButton(button, forUserId: userId)
            buttons.append(button) // Add button to the local array
            sortButtons() // Ensure buttons remain sorted by order
        } catch {
            errorMessage = "Failed to add button: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete Button
    func deleteButton(_ button: ButtonObject) async {
        guard let index = buttons.firstIndex(where: { $0.id == button.id }) else { return }
        do {
            try await FirebaseService.shared.deleteButtonObject(button.id, forUserId: userId)
            buttons.remove(at: index)
            updateOrdersAfterDeletion() // Recalculate orders for remaining buttons
        } catch {
            errorMessage = "Failed to delete button: \(error.localizedDescription)"
        }
    }

    // MARK: - Update Button (metadata)
    func updateButton(_ updated: ButtonObject) async {
        do {
            let doc = db
                .collection("users")
                .document(userId)
                .collection("buttons")
                .document(updated.id)

            // Update ONLY metadata fields here. Do NOT write the tallies map from edits.
            try await doc.setData([
                "name": updated.name,
                "cost": updated.cost,
                "color": updated.color,
                "groupId": updated.group,
                "order": updated.order,
                "image": updated.image
            ], merge: true)
        } catch {
            self.errorMessage = "Failed to update button: \(error.localizedDescription)"
        }

        // Reflect changes locally
        if let idx = buttons.firstIndex(where: { $0.id == updated.id }) {
            buttons[idx].name = updated.name
            buttons[idx].cost = updated.cost
            buttons[idx].color = updated.color
            buttons[idx].group = updated.group
            buttons[idx].order = updated.order
            buttons[idx].image = updated.image
            sortButtons()
        }
    }

    // MARK: - Save Order
    func saveOrder() async {
        do {
            for (index, button) in buttons.enumerated() {
                try await FirebaseService.shared.updateButtonOrder(
                    buttonId: button.id,
                    forUserId: userId,
                    order: index
                )
            }
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }

    // MARK: - Filter Buttons by Group
    func buttons(for group: String) -> [ButtonObject] {
        buttons.filter { $0.group == group }
    }

    // MARK: - Reorder Buttons
    func reorderButtons(from source: IndexSet, to destination: Int, in group: String) async {
        var filteredButtons = buttons(for: group) // Buttons filtered by group
        filteredButtons.move(fromOffsets: source, toOffset: destination)

        // Update the original buttons array
        for (index, button) in filteredButtons.enumerated() {
            if let originalIndex = buttons.firstIndex(where: { $0.id == button.id }) {
                buttons[originalIndex].order = index
            }
        }

        // Immediately sort buttons locally for UI update
        buttons.sort(by: { $0.order < $1.order })

        // Persist the changes asynchronously
        Task {
            await saveOrder()
        }
    }
    
    // MARK: - Reset All Tallies for a Specific Date
    func resetAllTallies(for date: Date) async {
        do {
            let allButtons = try await FirebaseService.shared.fetchButtonObjects(forUserId: userId, date: date)
            
            // Reset tallies in Firestore
            for button in allButtons {
                try await self.updateTallyInFirestore(for: button, tally: 0, date: date)
            }

            let key = DateAuthority.deviceDayKey(for: date)
            self.buttons = allButtons.map { var b = $0; b.tallies[key] = 0; return b }
        } catch {
            self.errorMessage = "Failed to reset tallies: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers
    private func sortButtons() {
        buttons.sort(by: { $0.order < $1.order }) // Sort buttons by their assigned order
    }

    private func updateOrdersAfterDeletion() {
        // Recalculate the order for all buttons sequentially
        for index in buttons.indices {
            buttons[index].order = index
        }
        Task {
            await saveOrder() // Save updated orders to Firestore
        }
    }


    /// Archive the previous day’s tallies and then load the appropriate data for newDate
    private func handleDateChange(_ newDate: Date) async {
        // Ensure any unsynced tallies are persisted before switching dates
        await flushPendingSyncs()

        // Ensure we have button metadata before archiving
        if buttons.isEmpty {
            await fetchButtons(for: previousDate)
        }

        let userDoc = db.collection("users").document(userId)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let newDay = cal.startOfDay(for: newDate)
        let newKey = DateAuthority.deviceDayKey(for: newDay)

        // 1) Archive if moving forward
        if newDate > previousDate, didHydrateToday {
            let oldDay = cal.startOfDay(for: previousDate)
            let oldKey = DateAuthority.deviceDayKey(for: oldDay)
            for button in buttons {
                let oldCount = button.tallies[oldKey] ?? 0
                let buttonDoc = userDoc.collection("buttons").document(button.id)
                try? await buttonDoc.setData([
                    "tallies.\(oldKey)": oldCount
                ], merge: true)
            }
            didHydrateToday = false
        }

        // 2) Load live or archived data
        if DateAuthority.isDeviceToday(newDate) {
            await fetchButtons(for: newDate)
        } else {
            var updatedButtons: [ButtonObject] = []
            for button in buttons {
                let docSnap = try? await userDoc
                    .collection("buttons")
                    .document(button.id)
                    .getDocument()
                let data = docSnap?.data() ?? [:]
                let nestedMap = data["tallies"] as? [String: Int] ?? [:]
                let direct = data["tallies.\(newKey)"] as? Int ?? 0
                let tally = max(nestedMap[newKey] ?? 0, direct)
                var b = button
                b.tallies = [newKey: tally]
                updatedButtons.append(b)
            }
            await MainActor.run {
                self.buttons = updatedButtons
            }
        }

        previousDate = newDate
    }

    /// Apply a live snapshot so that the in-memory state reflects the *selected* local day,
    /// preserving pending increments for today and trusting server values for past days.
    private func applySnapshot(_ snapshot: [ButtonObject], for date: Date) {
        if DateAuthority.isDeviceToday(date) {
            let key = DateAuthority.deviceDayKey(for: date)
            let existing = Dictionary(uniqueKeysWithValues: self.buttons.map { ($0.id, $0.tallies[key] ?? 0) })
            let pending = self.pendingSyncs

            let merged: [ButtonObject] = snapshot.map { btn in
                var b = btn
                let local = existing[btn.id] ?? 0
                let server = btn.tallies[key] ?? 0
                let pendingKey = "\(btn.id)|\(key)"
                if pending[pendingKey] != nil {
                    b.tallies[key] = max(local, server)
                } else {
                    b.tallies[key] = server
                }
                return b
            }
            self.buttons = merged
            self.sortButtons()
        } else {
            let key = DateAuthority.deviceDayKey(for: date)
            let coerced: [ButtonObject] = snapshot.map { btn in
                var b = btn
                let onlyThisDay = b.tallies[key] ?? 0
                b.tallies = [key: onlyThisDay]
                return b
            }
            self.buttons = coerced
            self.sortButtons()
        }
    }
}

