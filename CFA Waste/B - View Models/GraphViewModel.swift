import Foundation
import Firebase
import FirebaseFirestore
import Combine


struct GroupedWasteItem: Identifiable {
    let id = UUID()
    let name: String
    let averageCostWasted: Double
}

struct GroupRef: Identifiable, Equatable {
    let id: String
    let name: String
    let order: Int
}


class GraphViewModel: ObservableObject {
    @Published var buttonObjects: [ButtonObject] = []
    @Published var totalAmount: Double = 0.0
    @Published var weeklyTotal: Double = 0.0
    @Published var weeklyData: [(date: String, total: Double)] = []
    @Published var monthlyWeeklyData: [(week: Int, total: Double)] = [] // Stores weekly totals for a 30-day window
    @Published var groupedWasteData: [String: [GroupedWasteItem]] = [:] // Grouped waste data for each group

    @Published var selectedDate: Date = Date()
    @Published var selectedButton: ButtonObject? = nil
    @Published var monthlyItemData: [(date: String, tally: Int)] = []
    @Published var groups: [GroupRef] = []
    
    private lazy var monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
    
    private var cancellables = Set<AnyCancellable>()

    private let userId: String
    private let db = Firestore.firestore()
    private var groupsListener: ListenerRegistration?

    init(userId: String) {
        self.userId = userId

        startGroupsListener()

        $groups
            .sink { [weak self] _ in
                Task { await self?.loadGroupedWasteData() }
            }
            .store(in: &cancellables)

        // Recompute whenever the selected date changes
        $selectedDate
            .removeDuplicates()
            .sink { [weak self] newDate in
                guard let self = self else { return }
                Task {
                    await self.loadButtonObjects(for: newDate)          // daily (single day)
                    await self.loadWeeklyData(relativeTo: newDate)      // last 7 days
                    await self.loadMonthlyWeeklyData(relativeTo: newDate) // 30 days split into 4x7-day segments
                    await self.loadGroupedWasteData()                   // grouped averages (last 7 days)
                }
            }
            .store(in: &cancellables)

        Task {
            await loadButtonObjects(for: selectedDate)
            await loadWeeklyData(relativeTo: selectedDate)
            await loadMonthlyWeeklyData(relativeTo: selectedDate)
            await loadGroupedWasteData()
        }
        
        // When buttonObjects loads, set the first selected and load its monthly data
        $buttonObjects
            .filter { !$0.isEmpty }
            .sink { [weak self] buttons in
                guard let self = self else { return }
                let firstButton = buttons.sorted { $0.name < $1.name }.first!
                self.selectedButton = firstButton
                Task { await self.loadMonthlyData(for: firstButton) }
            }
            .store(in: &cancellables)
        
        // Reload monthly data whenever the selected button changes
        $selectedButton
            .compactMap { $0 }
            .sink { [weak self] button in
                Task { await self?.loadMonthlyData(for: button) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Button Data for Selected Date (single day)
    func loadButtonObjects(for date: Date) async {
        let formattedDate = formatDate(date)
        do {
            let buttons = try await fetchButtonObjects(userId: userId, date: formattedDate)
            DispatchQueue.main.async {
                self.buttonObjects = buttons
                self.calculateTotalAmount(for: formattedDate)
                print("✅ Loaded \(buttons.count) button objects for \(formattedDate)")
            }
        } catch {
            print("❌ Error fetching buttons: \(error)")
        }
    }

    // MARK: - Load Weekly Totals (Past 7 Days)
    func loadWeeklyData(relativeTo date: Date) async {
        let keys = lastNDaysKeys(startingFrom: date, count: 7) // inclusive of selected day
        do {
            let buttons = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            // Build rows by date key
            var newData: [(date: String, total: Double)] = []
            for k in keys {
                let dayTotal = buttons.reduce(0.0) { partial, b in
                    partial + (Double(b.tallies[k] ?? 0) * b.cost)
                }
                newData.append((date: k, total: dayTotal))
            }
            DispatchQueue.main.async {
                self.weeklyData = newData // already in chronological order from lastNDaysKeys()
                self.weeklyTotal = newData.reduce(0) { $0 + $1.total }
                print("📊 Weekly Data: \(self.weeklyData)")
            }
        } catch {
            print("❌ Error fetching weekly data: \(error)")
            DispatchQueue.main.async {
                self.weeklyData = keys.map { ($0, 0) }
                self.weeklyTotal = 0
            }
        }
    }

    // MARK: - Load Monthly Weekly Data (30 days split into 4x7-day segments)
    func loadMonthlyWeeklyData(relativeTo date: Date) async {
        let allKeys = lastNDaysKeys(startingFrom: date, count: 30)
        // 4 segments of 7 days (the remaining 2 days are ignored for the 4-week rollup)
        let segments: [[String]] = stride(from: 0, to: 28, by: 7).map { Array(allKeys[$0..<$0+7]) }
        do {
            let buttons = try await fetchButtonsWithTallies(userId: userId, dateKeys: allKeys)
            var newMonthlyData: [(week: Int, total: Double)] = []
            for (i, seg) in segments.enumerated() {
                let totalForWeek = seg.reduce(0.0) { subtotal, key in
                    subtotal + buttons.reduce(0.0) { $0 + (Double($1.tallies[key] ?? 0) * $1.cost) }
                }
                newMonthlyData.append((week: i + 1, total: totalForWeek))
            }
            DispatchQueue.main.async {
                self.monthlyWeeklyData = newMonthlyData
                print("📊 Monthly Weekly Data: \(self.monthlyWeeklyData)")
            }
        } catch {
            print("❌ Error fetching monthly weekly data: \(error)")
            DispatchQueue.main.async { self.monthlyWeeklyData = [] }
        }
    }

    // MARK: - Load Grouped Waste Data for Last 7 Days
    func loadGroupedWasteData() async {
        let keys = lastNDaysKeys(startingFrom: selectedDate, count: 7)
        do {
            let buttons = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var newGroupedWasteData: [String: [GroupedWasteItem]] = [:]

            guard !groups.isEmpty else {
                DispatchQueue.main.async { self.groupedWasteData = [:] }
                return
            }

            for group in groups.sorted(by: { lhs, rhs in
                lhs.order == rhs.order
                    ? (lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending)
                    : (lhs.order < rhs.order)
            }) {
                var groupItems: [GroupedWasteItem] = []
                let idKey = group.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let nameKey = group.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let filtered = buttons.filter { btn in
                    let g = btn.group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return g == idKey || g == nameKey
                }
                for button in filtered {
                    let totalWasteCost = keys.reduce(0.0) { subtotal, k in
                        subtotal + (Double(button.tallies[k] ?? 0) * button.cost)
                    }
                    let averageWasteCost = keys.isEmpty ? 0 : (totalWasteCost / Double(keys.count))
                    groupItems.append(GroupedWasteItem(name: button.name, averageCostWasted: averageWasteCost))
                }
                newGroupedWasteData[group.name] = groupItems
            }
            DispatchQueue.main.async {
                self.groupedWasteData = newGroupedWasteData
                print("📊 Grouped Waste Data (dynamic): \(self.groupedWasteData)")
            }
        } catch {
            print("❌ Error fetching grouped waste data: \(error)")
            DispatchQueue.main.async { self.groupedWasteData = [:] }
        }
    }

    // MARK: - Fetch ButtonObjects for ONE date (kept for daily views)
    private func fetchButtonObjects(userId: String, date: String) async throws -> [ButtonObject] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("buttons")
            .order(by: "order", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let data = document.data()

            if let name = data["name"] as? String,
               let order = data["order"] as? Int {
                let image = data["image"] as? String ?? ""
                let color = data["color"] as? String ?? "#FFFFFF"
                let cost = (data["cost"] as? Double) ?? Double((data["cost"] as? Int) ?? 0)

                // Prefer new `groupId`, fall back to legacy `group`
                let gid = (data["groupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let legacy = (data["group"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let groupUnified = (gid?.isEmpty == false ? gid! : (legacy ?? ""))

                // Read nested map and flat dotted; use the higher of the two
                let allTallies = data["tallies"] as? [String: Int] ?? [:]
                let nestedValue = allTallies[date] ?? 0
                let directValue = data["tallies.\(date)"] as? Int ?? 0
                let tallyForDate = max(nestedValue, directValue)
                let tallies = [ date: tallyForDate ]

                return ButtonObject(
                    id: document.documentID,
                    image: image,
                    color: color,
                    name: name,
                    cost: cost,
                    tallies: tallies,
                    group: groupUnified,
                    order: order
                )
            } else {
                print("⚠️ Missing fields in document \(document.documentID). Using fallback values.")
                return ButtonObject(
                    id: document.documentID,
                    image: "",
                    color: "#FFFFFF",
                    name: "Unknown",
                    cost: 0.0,
                    tallies: [:],
                    group: "Uncategorized",
                    order: 0
                )
            }
        }
    }

    // MARK: - Fetch ButtonObjects with tallies across MANY dates (for weekly/monthly/custom)
    private func fetchButtonsWithTallies(userId: String, dateKeys: [String]) async throws -> [ButtonObject] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("buttons")
            .order(by: "order", descending: false)
            .getDocuments()

        var results: [ButtonObject] = []
        results.reserveCapacity(snapshot.documents.count)

        for document in snapshot.documents {
            let data = document.data()
            let name  = (data["name"] as? String) ?? "Unnamed"
            let image = (data["image"] as? String) ?? ""
            let color = (data["color"] as? String) ?? "#FFFFFF"
            let cost  = (data["cost"] as? Double) ?? Double((data["cost"] as? Int) ?? 0)
            let gid = (data["groupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let legacy = (data["group"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = (gid?.isEmpty == false ? gid! : (legacy ?? ""))
            let order = (data["order"] as? Int) ?? 0

            let nested = data["tallies"] as? [String:Int] ?? [:]
            var tallies: [String:Int] = [:]
            tallies.reserveCapacity(dateKeys.count)
            for k in dateKeys {
                let direct = data["tallies.\(k)"] as? Int ?? 0
                tallies[k] = max(nested[k] ?? 0, direct)
            }

            results.append(ButtonObject(
                id: document.documentID,
                image: image,
                color: color,
                name: name,
                cost: cost,
                tallies: tallies,
                group: group,
                order: order
            ))
        }
        return results
    }

    // MARK: - Public: Fetch items with tallies for arbitrary date keys (optionally filtered by IDs)
    func fetchItemsWithTallies(dateKeys: [String], filterIDs: Set<String>? = nil) async -> [ButtonObject] {
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: dateKeys)
            if let ids = filterIDs, !ids.isEmpty {
                return items.filter { ids.contains($0.id) }
            }
            return items
        } catch {
            print("❌ fetchItemsWithTallies error: \(error)")
            return []
        }
    }

    // MARK: - Timeframe Helpers (Keys)
    /// Keys FORWARD from a start date (inclusive). E.g., Monthly = 30 days from start.
    private func nextNDaysKeys(startingFrom start: Date, count: Int) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current // Device local day boundary
        let start = cal.startOfDay(for: start)
        var arr: [String] = []
        arr.reserveCapacity(count)
        for i in 0..<count {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                arr.append(formatDate(d))
            }
        }
        return arr
    }

    /// Inclusive keys between start and end, moving forward by 1 day
    private func keysBetween(start: Date, end: Date) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current // Device local day boundary
        let s = cal.startOfDay(for: min(start, end))
        let e = cal.startOfDay(for: max(start, end))
        var res: [String] = []
        var d = s
        while d <= e {
            res.append(formatDate(d))
            guard let nd = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = nd
        }
        return res
    }

    // MARK: - Totals Over Timeframes (Overall)
    /// Daily overall totals for a single date (across all items)
    func getDailyTotal(on date: Date) async -> (tally: Int, cost: Double) {
        let key = formatDate(date)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: [key])
            var totalTally = 0
            var totalCost  = 0.0
            for item in items {
                let t = item.tallies[key] ?? 0
                totalTally += t
                totalCost  += Double(t) * item.cost
            }
            return (totalTally, totalCost)
        } catch {
            print("❌ getDailyTotal error: \(error)")
            return (0, 0)
        }
    }

    /// Weekly overall totals for 7 days FORWARD from a given start date (inclusive)
    func getWeeklyTotals(startingFrom startDate: Date) async -> (tally: Int, cost: Double) {
        let keys = nextNDaysKeys(startingFrom: startDate, count: 7)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var totalTally = 0
            var totalCost  = 0.0
            for item in items {
                let t = keys.reduce(0) { $0 + (item.tallies[$1] ?? 0) }
                totalTally += t
                totalCost  += Double(t) * item.cost
            }
            return (totalTally, totalCost)
        } catch {
            print("❌ getWeeklyTotals error: \(error)")
            return (0, 0)
        }
    }

    /// Monthly overall totals for 30 days FORWARD from a given start date (inclusive)
    func getMonthlyTotal(from startDate: Date) async -> (tally: Int, cost: Double) {
        let keys = nextNDaysKeys(startingFrom: startDate, count: 30)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var totalTally = 0
            var totalCost  = 0.0
            for item in items {
                let t = keys.reduce(0) { $0 + (item.tallies[$1] ?? 0) }
                totalTally += t
                totalCost  += Double(t) * item.cost
            }
            return (totalTally, totalCost)
        } catch {
            print("❌ getMonthlyTotal error: \(error)")
            return (0, 0)
        }
    }

    /// Custom overall totals for an inclusive start...end date range
    func getCustomTotal(from startDate: Date, to endDate: Date) async -> (tally: Int, cost: Double) {
        let keys = keysBetween(start: startDate, end: endDate)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var totalTally = 0
            var totalCost  = 0.0
            for item in items {
                let t = keys.reduce(0) { $0 + (item.tallies[$1] ?? 0) }
                totalTally += t
                totalCost  += Double(t) * item.cost
            }
            return (totalTally, totalCost)
        } catch {
            print("❌ getCustomTotal error: \(error)")
            return (0, 0)
        }
    }

    // MARK: - Per-Item Totals for a Timeframe
    /// Per-item totals over an inclusive date range (use for Weekly, Monthly, Custom). Optionally filter to selected IDs.
    func getPerItemTotals(from startDate: Date, to endDate: Date, filterIDs: Set<String>? = nil) async -> [String: (tally: Int, cost: Double)] {
        let keys = keysBetween(start: startDate, end: endDate)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var result: [String: (Int, Double)] = [:]
            for item in items {
                if let f = filterIDs, !f.isEmpty, !f.contains(item.id) { continue }
                let t = keys.reduce(0) { $0 + (item.tallies[$1] ?? 0) }
                result[item.id] = (t, Double(t) * item.cost)
            }
            return result
        } catch {
            print("❌ getPerItemTotals error: \(error)")
            return [:]
        }
    }


    /// Convenience: per-item totals for a single day
    func getPerItemDailyTotals(on date: Date, filterIDs: Set<String>? = nil) async -> [String: (tally: Int, cost: Double)] {
        return await getPerItemTotals(from: date, to: date, filterIDs: filterIDs)
    }

    // MARK: - Week-over-Week (same weekday) helpers
    /// Device-local start of day for stable day comparisons regardless of time of day
    private func deviceLocalStartOfDay(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.startOfDay(for: date)
    }

    /// Returns the same weekday one week (7 days) prior in device-local time.
    private func sameWeekdayLastWeek(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: -7, to: start) ?? start
    }

    /// Convenience: total cost for a single day (optionally filtered to a set of item IDs)
    @MainActor
    func getDailyCost(on date: Date, filterIDs: Set<String>? = nil) async -> Double {
        let start = deviceLocalStartOfDay(date)
        let perItem = await getPerItemDailyTotals(on: start, filterIDs: filterIDs)
        return perItem.values.reduce(0.0) { $0 + $1.1 }
    }

    /// Convenience: today's cost, last week's same-weekday cost, and percent change.
    /// Percent is ((today - lastWeek) / lastWeek) * 100. If lastWeek is 0, returns 0% when today is 0, otherwise +100%.
    @MainActor
    func getTodayWoW(filterIDs: Set<String>? = nil) async -> (today: Double, lastWeek: Double, percent: Double) {
        let todayDate = Date()
        let lastWeekDate = sameWeekdayLastWeek(from: todayDate)
        let todayTotal = await getDailyCost(on: todayDate, filterIDs: filterIDs)
        let lastWeekTotal = await getDailyCost(on: lastWeekDate, filterIDs: filterIDs)
        let percent: Double
        if lastWeekTotal == 0 {
            percent = todayTotal == 0 ? 0.0 : 100.0
        } else {
            percent = ((todayTotal - lastWeekTotal) / lastWeekTotal) * 100.0
        }
        return (todayTotal, lastWeekTotal, percent)
    }

    /// Convenience: per-item totals for 7 days FORWARD from start
    func getPerItemWeeklyTotals(startingFrom startDate: Date, filterIDs: Set<String>? = nil) async -> [String: (tally: Int, cost: Double)] {
        let keys = nextNDaysKeys(startingFrom: startDate, count: 7)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var result: [String: (Int, Double)] = [:]
            for item in items {
                if let f = filterIDs, !f.isEmpty, !f.contains(item.id) { continue }
                let t = keys.reduce(0) { $0 + (item.tallies[$1] ?? 0) }
                result[item.id] = (t, Double(t) * item.cost)
            }
            return result
        } catch {
            print("❌ getPerItemWeeklyTotals error: \(error)")
            return [:]
        }
    }

    /// Convenience: per-item totals for 30 days FORWARD from start
    func getPerItemMonthlyTotals(from startDate: Date, filterIDs: Set<String>? = nil) async -> [String: (tally: Int, cost: Double)] {
        let keys = nextNDaysKeys(startingFrom: startDate, count: 30)
        do {
            let items = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            var result: [String: (Int, Double)] = [:]
            for item in items {
                if let f = filterIDs, !f.isEmpty, !f.contains(item.id) { continue }
                let t = keys.reduce(0) { $0 + (item.tallies[$1] ?? 0) }
                result[item.id] = (t, Double(t) * item.cost)
            }
            return result
        } catch {
            print("❌ getPerItemMonthlyTotals error: \(error)")
            return [:]
        }
    }

    // MARK: - Get Weekly Total Cost
    func getWeeklyTotal() -> Double {
        // Sum the totals for the past seven days loaded in weeklyData
        return weeklyData.map { $0.total }.reduce(0, +)
    }

    // MARK: - Get Total Cost for a Specific Button on a Date
    func getTotalCost(for button: ButtonObject, on date: String) -> Double {
        return Double(getTally(for: button, on: date)) * button.cost
    }

    // MARK: - Get Tally for a Specific Button on a Date
    func getTally(for button: ButtonObject, on date: String) -> Int {
        // Support both shapes in in-memory map as well
        return button.tallies[date] ?? button.tallies["tallies.\(date)"] ?? 0
    }

    // MARK: - Update Tally in Firestore
    func updateTally(for button: ButtonObject, newTally: Int, date: Date) async {
        let formattedDate = formatDate(date)
        let buttonRef = db.collection("users").document(userId).collection("buttons").document(button.id)

        do {
            try await buttonRef.updateData(["tallies.\(formattedDate)": newTally])
            DispatchQueue.main.async {
                if let index = self.buttonObjects.firstIndex(where: { $0.id == button.id }) {
                    var updatedButtons = self.buttonObjects
                    updatedButtons[index].tallies[formattedDate] = newTally
                    self.buttonObjects = updatedButtons // Forces UI refresh
                    self.calculateTotalAmount(for: formattedDate)
                }
            }
        } catch {
            print("❌ Error updating tally: \(error)")
        }
    }

    // MARK: - Calculate Total Amount for a Given Date
    private func calculateTotalAmount(for date: String) {
        let newTotal = self.buttonObjects.reduce(0) { total, button in
            total + self.getTotalCost(for: button, on: date)
        }

        DispatchQueue.main.async {
            self.totalAmount = newTotal
            print("💰 Updated total amount for \(date): \(self.totalAmount)")
        }
    }

    /// Returns the date-key for the device's local "today" (regardless of time of day)
    var deviceLocalTodayKey: String { DateAuthority.todayKey }

    // MARK: - Date Helpers
    func formatDate(_ date: Date) -> String {
        DateAuthority.deviceDayKey(for: date)
    }

    private func lastNDaysKeys(startingFrom anchor: Date, count: Int) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.startOfDay(for: anchor)
        var arr: [String] = []
        arr.reserveCapacity(count)
        for i in stride(from: count - 1, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -i, to: start) {
                arr.append(formatDate(d))
            }
        }
        return arr
    }
    
    /// Load tallies for the past 30 days for a given button
    func loadMonthlyData(for button: ButtonObject) async {
        let keys = lastNDaysKeys(startingFrom: selectedDate, count: 30)
        do {
            let buttons = try await fetchButtonsWithTallies(userId: userId, dateKeys: keys)
            let map = buttons.first(where: { $0.id == button.id })?.tallies ?? [:]
            var newData: [(date: String, tally: Int)] = []
            newData.reserveCapacity(keys.count)
            for k in keys {
                // Display uses MM/dd while key stays yyyy-MM-dd
                if let dateObj = ISO8601DateFormatter.yyyyMMdd.date(from: k) {
                    newData.append((date: monthDayFormatter.string(from: dateObj), tally: map[k] ?? 0))
                } else {
                    newData.append((date: k, tally: map[k] ?? 0))
                }
            }
            DispatchQueue.main.async { self.monthlyItemData = newData }
        } catch {
            DispatchQueue.main.async { self.monthlyItemData = [] }
        }
    }
    deinit {
        groupsListener?.remove()
        groupsListener = nil
    }
}

// MARK: - Small ISO Helper
private extension ISO8601DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
// MARK: - Dynamic Groups Listener
private extension GraphViewModel {
    func startGroupsListener() {
        groupsListener?.remove()

        let userDoc = db.collection("users").document(userId)
        groupsListener = userDoc
            .collection("groups")
            .order(by: "order", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Groups listen error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let mapped: [GroupRef] = docs.map { doc in
                    let data = doc.data()
                    let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? doc.documentID
                    let order = data["order"] as? Int ?? 0
                    return GroupRef(id: doc.documentID, name: name, order: order)
                }
                self.groups = mapped.sorted { (a, b) in
                    if a.order == b.order { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
                    return a.order < b.order
                }
            }
    }
}


