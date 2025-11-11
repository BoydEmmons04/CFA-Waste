import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - Report Types
fileprivate enum ReportScope: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case custom = "Custom"
    var id: String { rawValue }
}

struct GraphView: View {
    @StateObject private var viewModel: GraphViewModel
    @Environment(\.dismiss) private var dismiss

    init(userId: String? = nil) {
        let uid = userId ?? Auth.auth().currentUser?.uid ?? "UnknownUser"
        _viewModel = StateObject(wrappedValue: GraphViewModel(userId: uid))
    }

    // MARK: - Selection state
    @State private var collapsedGroups: Set<String> = []

    // Persist last-used scope and dates
    @AppStorage("GraphView.scopeRaw") private var storedScopeRaw: String = ReportScope.daily.rawValue
    @AppStorage("GraphView.startKey") private var storedStartKey: String = ""
    @AppStorage("GraphView.endKey") private var storedEndKey: String = ""
    @AppStorage("GraphView.selectedGroup") private var storedGroup: String = "__ALL__"
    @State private var selectedGroup: String = "__ALL__"

    // Hydration state
    @State private var hydratedItems: [ButtonObject] = []
    @State private var isHydrating: Bool = false
    @State private var perItemTotals: [String: (Int, Double)] = [:]
    // Banner animation state
    @State private var bannerPulse: Bool = false
    // Detail presentation (use item identity for the sheet)
    @State private var detailItem: ButtonObject? = nil
    @State private var showSignOutConfirm: Bool = false

    // Banner totals (today vs last week) sourced from GraphViewModel
    @State private var bannerToday: Double = 0
    @State private var bannerLastWeek: Double = 0
    @State private var bannerPercent: Double = 0

    // MARK: - Report scope & dates
    @State private var scope: ReportScope = .daily
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())


    // MARK: - Limits
    private let allGroupToken = "__ALL__"

    var body: some View {
        VStack(spacing: 8) {
            todayBanner
            if isPad {
                ipadBody
            } else {
                iphoneBody
            }
        }
        .padding(.top, 8)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isPad {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .imageScale(.medium)
                    }
                } else {
                    Button(action: { showSignOutConfirm = true }) {
                        Text("Sign Out")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    .tint(.red)
                }
            }
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) { signOut() }
        } message: {
            Text("You'll need to log in again to continue.")
        }
        .onAppear {
            if let s = ReportScope(rawValue: storedScopeRaw) { scope = s }
            if let d = Self.dateFromKey(storedStartKey) { startDate = d }
            if let e = Self.dateFromKey(storedEndKey) { endDate = e }
            selectedGroup = storedGroup
            Task { await hydrateData() }
            Task { await refreshBannerTotals() }
            // Subtle initial pulse
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                bannerPulse.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    bannerPulse.toggle()
                }
            }
        }
        .onChange(of: scope) { newScope in
            storedScopeRaw = newScope.rawValue
            Task { await hydrateData() }
        }
        .onChange(of: startDate) { newStart in
            storedStartKey = Self.key(for: newStart)
            Task { await hydrateData() }
        }
        .onChange(of: endDate) { newEnd in
            storedEndKey = Self.key(for: newEnd)
            Task { await hydrateData() }
        }
        .onChange(of: selectedGroup) { newValue in
            storedGroup = newValue
            Task { await hydrateData() }
            Task { await refreshBannerTotals() }
        }
        .sheet(item: $detailItem) { item in
            DetailBreakdownView(
                item: item,
                rows: rows,
                rowData: rowData,
                scope: scope
            )
        }
    }

    // MARK: - Adaptive Bodies
    private var ipadBody: some View {
        VStack(spacing: 12) {
            headerControls
            Divider()
            reportTable
            totalsFooter
        }
    }

    private var iphoneBody: some View {
        VStack(spacing: 10) {
            phoneHeaderControls
            Divider()
            phoneReportTable
            phoneTotalsFooter
        }
    }
}

// MARK: - UI Sections
private extension GraphView {
    // MARK: - Phone UI Sections
    var phoneHeaderControls: some View {
        VStack(spacing: 8) {
            // Scope (segmented)
            Picker("Scope", selection: $scope) {
                ForEach(ReportScope.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            // Dates (compact)
            Group {
                switch scope {
                case .daily:
                    DatePicker("Date", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                case .weekly:
                    DatePicker("Week start (7 days)", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                case .monthly:
                    DatePicker("Month start (30 days)", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                case .custom:
                    VStack(spacing: 6) {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        DatePicker("End", selection: $endDate, in: startDate...Date.distantFuture, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
            }

            // Group (segmented if small, menu if many)
            VStack(alignment: .leading, spacing: 6) {
                if groupKeys.count <= 4 {
                    Picker("Group", selection: $selectedGroup) {
                        ForEach(groupKeys, id: \.self) { key in
                            Text(displayName(for: key)).tag(key)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } else {
                    Picker("Group", selection: $selectedGroup) {
                        ForEach(groupKeys, id: \.self) { key in
                            Text(displayName(for: key)).tag(key)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
        }
        .padding(.horizontal)
    }


    var phoneReportTable: some View {
        ZStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                if selectedItems.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "list.bullet", description: Text("This group has no items."))
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        let columns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 10)]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(selectedItems, id: \.id) { item in
                                let totals = columnTotals[item.id] ?? (0, 0.0)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        ColorSwatch(hex: item.color)
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text("$\(item.cost, specifier: "%.2f") per unit")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("\(totals.0)")
                                            .font(.system(size: 30, weight: .semibold))
                                            .monospacedDigit()
                                        Text("$\(totals.1, specifier: "%.2f") total")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                    Text(scope == .monthly ? "Tap to see weekly breakdown" : "Tap to see daily breakdown")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    detailItem = item
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .disabled(isHydrating)
                    .overlay(
                        Group { if isHydrating { Color.black.opacity(0.03) } }
                    )
                }
            }

            if isHydrating {
                ProgressView("Loading…")
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    .shadow(radius: 2)
            }
        }
    }

    var phoneTotalsFooter: some View {
        let grand = grandTotals
        return HStack {
            Spacer()
            HStack(spacing: 8) {
                Text("Grand Total:")
                    .font(.headline)
                Text("\(grand.tally) • $\(grand.cost, specifier: "%.2f")")
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            Spacer()
        }
        .padding(.horizontal)
    }
    var headerControls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Scope", selection: $scope) {
                    ForEach(ReportScope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                Spacer(minLength: 8)
            }

            // Date controls
            Group {
                switch scope {
                case .daily:
                    DatePicker("Date", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                case .weekly:
                    DatePicker("Week start (7 days)", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                case .monthly:
                    DatePicker("Month start (30 days)", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                case .custom:
                    HStack {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        DatePicker("End", selection: $endDate, in: startDate...Date.distantFuture, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("Group")
                if groupKeys.count <= 5 {
                    Picker("Group", selection: $selectedGroup) {
                        ForEach(groupKeys, id: \.self) { key in
                            Text(displayName(for: key)).tag(key)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } else {
                    Picker("Group", selection: $selectedGroup) {
                        ForEach(groupKeys, id: \.self) { key in
                            Text(displayName(for: key)).tag(key)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal)
    }

    var reportTable: some View {
        ZStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                if selectedItems.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "list.bullet", description: Text("This group has no items."))
                        .frame(maxWidth: .infinity)
                } else {
                    // SUMMARY GRID — no horizontal scrolling
                    ScrollView(.vertical, showsIndicators: true) {
                        let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(selectedItems, id: \.id) { item in
                                let totals = columnTotals[item.id] ?? (0, 0.0)
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 10) {
                                        ColorSwatch(hex: item.color)
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text("$\(item.cost, specifier: "%.2f") per unit")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }

                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text("\(totals.0)")
                                            .font(.system(size: 34, weight: .semibold))
                                            .monospacedDigit()
                                        Text("$\(totals.1, specifier: "%.2f") total")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }

                                    Text(scope == .monthly ? "Tap to see weekly breakdown" : "Tap to see daily breakdown")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    // Optional little preview row of the last label
                                    if let lastIdx = rows.indices.last {
                                        let lastLabel = rows[lastIdx]
                                        let r = rowData[lastIdx]
                                        let tally = r[item.id] ?? 0
                                        let price = Double(tally) * item.cost
                                        HStack {
                                            Text(lastLabel)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("\(tally)  •  $\(price, specifier: "%.2f")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .monospacedDigit()
                                        }
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    detailItem = item
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .disabled(isHydrating)
                    .overlay(
                        Group { if isHydrating { Color.black.opacity(0.03) } }
                    )
                }
            }

            if isHydrating {
                ProgressView("Loading…")
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    .shadow(radius: 2)
            }
        }
    }
// MARK: - Detail Breakdown
fileprivate struct DetailBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    let item: ButtonObject
    let rows: [String]
    let rowData: [[String:Int]]
    let scope: ReportScope

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 10) {
                        ColorSwatch(hex: item.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.headline)
                            Text("$\(item.cost, specifier: "%.2f") per unit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }

                Section(header: Text(scope == .monthly ? "Weekly Breakdown" : "Daily Breakdown")) {
                    ForEach(rows.indices, id: \.self) { idx in
                        let label = rows[idx]
                        let r = rowData[idx]
                        let tally = r[item.id] ?? 0
                        let price = Double(tally) * item.cost
                        HStack {
                            Text(label)
                            Spacer()
                            HStack(spacing: 8) {
                                Text("\(tally)")
                                    .font(.headline)
                                    .monospacedDigit()
                                Text("$\(price, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Totals footer
                Section {
                    let totalTally = rowData.reduce(0) { $0 + ($1[item.id] ?? 0) }
                    let totalCost  = Double(totalTally) * item.cost
                    HStack {
                        Text("Total")
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(totalTally)")
                                .font(.headline)
                                .monospacedDigit()
                            Text("$\(totalCost, specifier: "%.2f")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

    var totalsFooter: some View {
        let grand = grandTotals
        return HStack {
            Spacer()
            HStack(spacing: 10) {
                Text("Grand Total:")
                    .font(.headline)
                Text("\(grand.tally) • $\(grand.cost, specifier: "%.2f")")
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            .padding(.trailing)
        }
    }
}

// MARK: - Data & Helpers
private extension GraphView {
    private func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("❌ Sign out failed: \(error.localizedDescription)")
        }
        dismiss()
    }

    var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return true
        #endif
    }

    // Always-on today total (device local day)
    private var todayKey: String { DateAuthority.todayKey }
    private var todayTotalDollars: Double { bannerToday }

    // Previous week same weekday key and total
    private var lastWeekKey: String {
        let cal = Calendar.current
        let lastWeek = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return Self.key(for: lastWeek)
    }

    private var lastWeekTotalDollars: Double { bannerLastWeek }

    // Week-over-week percentage change (always returns a value)
    private var wowChange: (text: String, color: Color) {
        let pct = bannerPercent
        let formatted = String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
        let color: Color = pct > 0 ? .red : (pct < 0 ? .green : .secondary)
        return (formatted, color)
    }

    private var todayBanner: some View {
        VStack(spacing: 4) {
            Text("Today's Total")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$\(todayTotalDollars, specifier: "%.2f")")
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                let wow = wowChange
                Text(wow.text)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(wow.color)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
        .scaleEffect(bannerPulse ? 1.045 : 1.0)
        .opacity(bannerPulse ? 1.0 : 0.98)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bannerPulse)
    }
    var groupKeys: [String] {
        if !viewModel.groups.isEmpty {
            let orderedIds = viewModel.groups
                .sorted { lhs, rhs in
                    lhs.order == rhs.order
                        ? (lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending)
                        : (lhs.order < rhs.order)
                }
                .map { $0.id }
            return [allGroupToken] + orderedIds
        }
        // Fallback: derive from items we have
        let keys = groupedItems.keys.sorted()
        return [allGroupToken] + keys
    }

    func displayName(for key: String) -> String {
        if key == allGroupToken { return "All" }
        if let g = viewModel.groups.first(where: { $0.id == key }) { return g.name }
        return key.isEmpty ? "(No Group)" : key
    }

    /// Resolve a group's name for a given id, if known from the ViewModel's groups list
    private func groupName(for id: String) -> String? {
        return viewModel.groups.first(where: { $0.id == id })?.name
    }

    var itemsInSelectedGroup: [ButtonObject] {
        let base: [ButtonObject]
        if selectedGroup == allGroupToken {
            base = items
        } else {
            let maybeName = groupName(for: selectedGroup)
            base = items.filter { btn in
                // Match by id (new) OR by name (legacy)
                btn.group == selectedGroup || (maybeName != nil && btn.group == maybeName)
            }
        }
        return base.sorted { lhs, rhs in
            if lhs.order == rhs.order { return lhs.name < rhs.name }
            return lhs.order < rhs.order
        }
    }
    // Build the list of date keys needed for the current scope, moving FORWARD from startDate
    func currentDateKeys() -> [String] {
        switch scope {
        case .daily:
            return [Self.key(for: startDate)]
        case .weekly:
            return Self.days(from: startDate, count: 7).map(Self.key(for:))
        case .monthly:
            return Self.days(from: startDate, count: 30).map(Self.key(for:))
        case .custom:
            return Self.days(from: startDate, to: max(endDate, startDate)).map(Self.key(for:))
        }
    }

    // Hydrate items for the selected group with tallies for the needed date keys via the ViewModel
    func hydrateData() async {
        await MainActor.run { isHydrating = true }
        defer { Task { await MainActor.run { isHydrating = false } } }
        let keys = currentDateKeys()
        let idsForGroup: Set<String> = Set(itemsInSelectedGroup.map { $0.id })
        guard !keys.isEmpty else {
            await MainActor.run {
                hydratedItems = []
                perItemTotals = [:]
            }
            return
        }
        // 1) Fetch items with per-day tallies for the table
        let fetched = await viewModel.fetchItemsWithTallies(dateKeys: keys, filterIDs: idsForGroup)

        // 2) Fetch per-item totals for the selected timeframe using the new ViewModel APIs
        var totals: [String: (Int, Double)] = [:]
        switch scope {
        case .daily:
            totals = await viewModel.getPerItemDailyTotals(on: startDate, filterIDs: idsForGroup)
        case .weekly:
            totals = await viewModel.getPerItemWeeklyTotals(startingFrom: startDate, filterIDs: idsForGroup)
        case .monthly:
            totals = await viewModel.getPerItemMonthlyTotals(from: startDate, filterIDs: idsForGroup)
        case .custom:
            let end = max(endDate, startDate)
            totals = await viewModel.getPerItemTotals(from: startDate, to: end, filterIDs: idsForGroup)
        }

        await MainActor.run {
            hydratedItems = Array(fetched)
            perItemTotals = totals
        }
    }

    /// Refresh today's total, last week's same-weekday total, and percent change using the ViewModel.
    func refreshBannerTotals() async {
        let filterIDs: Set<String>? = (selectedGroup == allGroupToken) ? nil : Set(itemsInSelectedGroup.map { $0.id })
        let result = await viewModel.getTodayWoW(filterIDs: filterIDs)
        await MainActor.run {
            bannerToday = result.today
            bannerLastWeek = result.lastWeek
            bannerPercent = result.percent
        }
    }

    var items: [ButtonObject] { viewModel.buttonObjects }

    var groupedItems: [String: [ButtonObject]] {
        Dictionary(grouping: items) { $0.group }
            .mapValues { list in
                list.sorted { lhs, rhs in
                    if lhs.order == rhs.order { return lhs.name < rhs.name }
                    return lhs.order < rhs.order
                }
            }
    }

    var selectedItems: [ButtonObject] {
        let base: [ButtonObject]
        if selectedGroup == allGroupToken {
            base = hydratedItems
        } else {
            let maybeName = groupName(for: selectedGroup)
            base = hydratedItems.filter { btn in
                btn.group == selectedGroup || (maybeName != nil && btn.group == maybeName)
            }
        }
        return base.sorted { lhs, rhs in
            if lhs.order == rhs.order { return lhs.name < rhs.name }
            return lhs.order < rhs.order
        }
    }

    var rows: [String] {
        switch scope {
        case .daily:
            let d = startDate
            return [Self.displayLabel(for: d)]
        case .weekly:
            return Self.days(from: startDate, count: 7).map { Self.displayLabel(for: $0) }
        case .monthly:
            let segments = Self.weekSegments(start: startDate, totalDays: 30)
            return segments.map { "\(Self.displayLabel(for: $0.start)) – \(Self.displayLabel(for: $0.end))" }
        case .custom:
            let range = Self.days(from: startDate, to: max(endDate, startDate))
            return range.map { Self.displayLabel(for: $0) }
        }
    }

    var rowData: [[String: Int]] {
        // Each element corresponds to rows[i], mapping itemID -> tally for that row
        switch scope {
        case .daily:
            let key = Self.key(for: startDate)
            return [totalsForDay(key: key)]
        case .weekly:
            let keys = Self.days(from: startDate, count: 7).map { d in Self.key(for: d) }
            var rows: [[String:Int]] = []
            rows.reserveCapacity(keys.count)
            for dayKey in keys {
                rows.append(totalsForDay(key: dayKey))
            }
            return rows
        case .monthly:
            let segments = Self.weekSegments(start: startDate, totalDays: 30)
            var rows: [[String:Int]] = []
            rows.reserveCapacity(segments.count)
            for seg in segments {
                let segDays = Self.days(from: seg.start, to: seg.end)
                let segKeys = segDays.map { d in Self.key(for: d) }
                rows.append(totalsForRange(keys: segKeys))
            }
            return rows
        case .custom:
            let days = Self.days(from: startDate, to: max(endDate, startDate))
            let keys = days.map { d in Self.key(for: d) }
            var rows: [[String:Int]] = []
            rows.reserveCapacity(keys.count)
            for dayKey in keys {
                rows.append(totalsForDay(key: dayKey))
            }
            return rows
        }
    }

    /// Support both shapes for tally keys:
    /// 1) Nested key: "yyyy-MM-dd"
    /// 2) Flat dotted key: "tallies.yyyy-MM-dd"
    private func tallyValue(for item: ButtonObject, dateKey: String) -> Int {
        if let v = item.tallies[dateKey] { return v }
        if let v = item.tallies["tallies.\(dateKey)"] { return v }
        return 0
    }

    func totalsForDay(key: String) -> [String: Int] {
        var dict: [String: Int] = [:]
        for item in selectedItems {
            dict[item.id] = tallyValue(for: item, dateKey: key)
        }
        return dict
    }

    func totalsForRange(keys: [String]) -> [String: Int] {
        var dict: [String: Int] = [:]
        for item in selectedItems {
            let sum = keys.reduce(0) { $0 + tallyValue(for: item, dateKey: $1) }
            dict[item.id] = sum
        }
        return dict
    }

    var columnTotals: [String: (Int, Double)] {
        // Prefer totals computed by the ViewModel over local aggregation,
        // because the VM merges Firestore nested + dotted shapes reliably.
        if !perItemTotals.isEmpty { return perItemTotals }
        var result: [String: (Int, Double)] = [:]
        for item in selectedItems {
            let totalTally = rowData.reduce(0) { $0 + ($1[item.id] ?? 0) }
            result[item.id] = (totalTally, Double(totalTally) * item.cost)
        }
        return result
    }

    var grandTotals: (tally: Int, cost: Double) {
        // Sum from perItemTotals (selected items only) when available
        if !perItemTotals.isEmpty {
            let t = perItemTotals.values.reduce(0) { $0 + $1.0 }
            let c = perItemTotals.values.reduce(0.0) { $0 + $1.1 }
            return (t, c)
        }
        // Fallback to computing from rowData
        let t = selectedItems.reduce(0) { $0 + (columnTotals[$1.id]?.0 ?? 0) }
        let c = selectedItems.reduce(0.0) { $0 + (columnTotals[$1.id]?.1 ?? 0.0) }
        return (t, c)
    }


}

// MARK: - Date Helpers
private extension GraphView {
    static func key(for date: Date) -> String {
        DateAuthority.deviceDayKey(for: date)
    }

    static func displayLabel(for date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeZone = TimeZone.current
        return df.string(from: date)
    }

    static func days(from start: Date, count: Int) -> [Date] {
        let cal = Calendar.current
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    static func days(from start: Date, to end: Date) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var d = start
        while d <= end { dates.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        return dates
    }

    static func weekSegments(start: Date, totalDays: Int) -> [(start: Date, end: Date)] {
        let cal = Calendar.current
        var segments: [(Date, Date)] = []
        var currentStart = start
        var remaining = totalDays
        while remaining > 0 {
            let len = min(7, remaining)
            let end = cal.date(byAdding: .day, value: len - 1, to: currentStart)!
            segments.append((currentStart, end))
            currentStart = cal.date(byAdding: .day, value: len, to: currentStart)!
            remaining -= len
        }
        return segments
    }


    // Parse yyyy-MM-dd back to Date
    static func dateFromKey(_ key: String) -> Date? {
        guard !key.isEmpty else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        // Returns a Date at local start-of-day for that key
        return df.date(from: key)
    }
}

// MARK: - Reusable Views
fileprivate struct ColorSwatch: View {
    let hex: String
    var body: some View {
        Circle()
            .fill(colorFromString(hex))
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
    }
    private func colorFromString(_ hexOrName: String) -> Color {
        if hexOrName.hasPrefix("#") {
            var hex = hexOrName
            hex.removeFirst()
            if hex.count == 6, let intVal = Int(hex, radix: 16) {
                let r = Double((intVal >> 16) & 0xFF) / 255.0
                let g = Double((intVal >> 8) & 0xFF) / 255.0
                let b = Double(intVal & 0xFF) / 255.0
                return Color(red: r, green: g, blue: b)
            }
        }
        return Color(hexOrName)
    }
}



// MARK: - Preview
struct GraphView_Previews: PreviewProvider {
    static var previews: some View {
        GraphView(userId: "preview")
    }
}

