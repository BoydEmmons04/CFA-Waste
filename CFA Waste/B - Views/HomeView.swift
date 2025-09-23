import SwiftUI

private func isUTCToday(_ d: Date) -> Bool {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = cal.startOfDay(for: d)
    let todayStart = cal.startOfDay(for: Date())
    return start == todayStart
}

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var buttonViewModel: ButtonGridViewModel
    @State private var selectedView: String = ""
    @State private var isShowingAddButtonView = false
    @State private var isMovingButtons = false
    @State private var isShowingSignOutAlert = false
    @Namespace private var categoryNS

    @State private var groups: [GroupInfo] = []

    // Dynamic items sourced from Firestore groups
    private var categoryItems: [(key: String, label: String)] {
        groups.map { ($0.id, $0.title) }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let current = groups.first(where: { $0.id == selectedView }) {
                    DynamicGroupView(
                        buttonGridVM: buttonViewModel,
                        groupId: current.id,
                        isMoving: $isMovingButtons,
                        selectedDate: buttonViewModel.selectedDate,
                        availableGroups: groups
                    )
                } else {
                    VStack(spacing: 12) {
                        if groups.isEmpty {
                            ProgressView()
                            Text("Loading groups…").foregroundColor(.secondary)
                        } else {
                            Text("Select a group").foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(" ") // ✅ Force toolbar to appear
            .navigationBarTitleDisplayMode(.inline)

        }
        .toolbar {
            // Sign Out Button (Leading)
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    isShowingSignOutAlert = true
                }) {
                    Text("Sign Out")
                        .foregroundColor(.red)
                }
            }

            // Centered Date Picker in Toolbar
            ToolbarItem(placement: .principal) {
                DatePicker("", selection: $buttonViewModel.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            // Add & Move Buttons (Trailing)
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    isShowingAddButtonView = true
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                }
                .disabled(!isUTCToday(buttonViewModel.selectedDate))

                Button(action: {
                    isMovingButtons.toggle()
                }) {
                    Image(systemName: isMovingButtons ? "checkmark" : "arrow.up.arrow.down.circle")
                        .font(.title2)
                }

                // Only show "Graph View" button on iPad
                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationLink("Graph View") {
                        GraphView()
                            .environmentObject(authViewModel)
                            .environmentObject(buttonViewModel)
                    }
                }
            }
        }
        .alert("Confirm Sign Out", isPresented: $isShowingSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                authViewModel.signOut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .sheet(isPresented: $isShowingAddButtonView) {
            AddButtonView(
                viewModel: buttonViewModel,
                group: selectedView,
                onGroupAdded: { newGroup in
                    if let idx = groups.firstIndex(where: { $0.id == newGroup.id }) {
                        groups[idx] = newGroup
                    } else {
                        groups.append(newGroup)
                    }
                    groups.sort { $0.order < $1.order }
                    selectedView = newGroup.id
                }
            )
        }
        .safeAreaInset(edge: .bottom) {
            AppStoreCategoryPicker(
                items: categoryItems,
                selection: $selectedView,
                ns: categoryNS
            )
            .padding(.bottom, 8)
        }
        .onAppear {
            let storeId = authViewModel.userId ?? "UnknownUser"
            FirebaseService.shared.listenGroups(forUserId: storeId, includeDisabled: false) { result in
                switch result {
                case .success(let fetched):
                    self.groups = fetched
                    if self.selectedView.isEmpty, let first = fetched.first { self.selectedView = first.id }
                case .failure(let err):
                    print("Groups listen error:", err)
                }
            }
        }
        .onDisappear {
            FirebaseService.shared.stopGroups()
        }
        
    }
}

// MARK: - Navigation Button
struct NavigationButton: View {
    let imageName: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack {
            Button(action: action) {
                VStack {
                    Image(systemName: imageName)
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .gray)
                    Text(label)
                        .font(.caption)
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
}

// MARK: - App Store–style Liquid Glass Category Picker
fileprivate struct AppStoreCategoryPicker: View {
    let items: [(key: String, label: String)]
    @Binding var selection: String
    var ns: Namespace.ID
    @Environment(\.colorScheme) private var scheme
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        ZStack {
            // Glassy background bar
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(scheme == .dark ? 0.12 : 0.18), lineWidth: 1)
                )

            GeometryReader { geo in
                let inset = max(0, (geo.size.width - contentWidth) / 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items, id: \.key) { item in
                            let isSelected = item.key == selection
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    selection = item.key
                                }
                            } label: {
                                Text(item.label)
                                    .font(.callout)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.clear)
                                    .contentShape(Rectangle())
                                    .anchorPreference(key: ChipFramesKey.self, value: .bounds) { [item.key: $0] }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(WidthMeasurer())
                    .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }
                    .padding(.vertical, 8)
                    .padding(.leading, inset + 8)
                    .padding(.trailing, inset + 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .overlayPreferenceValue(ChipFramesKey.self) { prefs in
                GeometryReader { proxy in
                    if let anchor = prefs[selection] {
                        let rect = proxy[anchor]
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.85),
                                        Color.white.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selection)
                    }
                }
            }
        }
        .frame(height: 88)
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }
}

// MARK: - Width Measuring Helpers
fileprivate struct WidthMeasurer: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentWidthKey.self, value: proxy.size.width)
        }
    }
}

fileprivate struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

fileprivate struct ChipFramesKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
