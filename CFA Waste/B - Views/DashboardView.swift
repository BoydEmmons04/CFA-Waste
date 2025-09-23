import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(userId: String) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(userId: userId))
    }

    @State private var groups: [GroupInfo] = []

    var body: some View {
        NavigationStack {
            VStack {
                Text("Daily Total: $\(viewModel.totalAmount, specifier: "%.2f")")
                    .font(.largeTitle)
                    .padding(.top)

                Text("Weekly Total: $\(String(format: "%.2f", viewModel.getWeeklyTotal()))")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .padding(.bottom)

                if viewModel.buttonObjects.isEmpty {
                    Text("No Data Available")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .padding()
                } else if groups.isEmpty {
                    ProgressView()
                        .padding()
                } else {
                    List {
                        ForEach(groups, id: \.id) { group in
                            let formattedDate = Self.dateFormatter.string(from: viewModel.selectedDate)

                            let totalForGroup = viewModel.buttonObjects
                                .filter { $0.group == group.id }
                                .map { viewModel.getTotalCost(for: $0, on: formattedDate) }
                                .reduce(0, +)

                            let sortedButtons = viewModel.buttonObjects
                                .filter { $0.group == group.id }
                                .sorted {
                                    viewModel.getTotalCost(for: $0, on: formattedDate) >
                                    viewModel.getTotalCost(for: $1, on: formattedDate)
                                }

                            if !sortedButtons.isEmpty {
                                Section(header:
                                    HStack {
                                        Text(group.title)
                                            .font(.title)
                                            .bold()
                                        Spacer()
                                        Text("$\(totalForGroup, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                ) {
                                    ForEach(sortedButtons) { button in
                                        HStack {
                                            Image(button.image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 40, height: 40)

                                            VStack(alignment: .leading) {
                                                Text(button.name)
                                                    .font(.headline)
                                                Text("$\(viewModel.getTotalCost(for: button, on: formattedDate), specifier: "%.2f")")
                                                    .font(.subheadline)
                                                    .foregroundColor(.gray)
                                            }

                                            Spacer()

                                            Text("\(viewModel.getTally(for: button, on: formattedDate))")
                                                .font(.title)
                                                .bold()
                                                .frame(width: 50, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Removed navigation title text
            .toolbar {
                // Logout button only appears on phones
                if UIDevice.current.userInterfaceIdiom == .phone {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            authViewModel.signOut()
                        }) {
                            Text("Logout")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Centered Date Picker
                ToolbarItem(placement: .principal) {
                    DatePicker("", selection: $viewModel.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: viewModel.selectedDate) { newDate in
                            Task {
                                await viewModel.loadButtonObjects(for: newDate)
                                await viewModel.loadWeeklyData(relativeTo: newDate)
                            }
                        }
                }
                
                // GraphView Button on the top right
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: GraphView().environmentObject(viewModel)) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                    }
                }
            }
            .onAppear {
                let storeId = authViewModel.userId ?? "UnknownUser"
                attachGroupsListener(for: storeId, includeDisabled: false)
                Task {
                    await viewModel.loadButtonObjects(for: viewModel.selectedDate)
                    await viewModel.loadWeeklyData(relativeTo: viewModel.selectedDate)
                }
            }
            .onDisappear {
                FirebaseService.shared.stopGroups()
            }
            .onChange(of: authViewModel.userId) { newId in
                FirebaseService.shared.stopGroups()
                let storeId = newId ?? "UnknownUser"
                attachGroupsListener(for: storeId, includeDisabled: false)
            }
        }
    }
    // MARK: - Groups listener
    private func attachGroupsListener(for storeId: String, includeDisabled: Bool) {
        FirebaseService.shared.listenGroups(forUserId: storeId, includeDisabled: includeDisabled) { result in
            switch result {
            case .success(let fetched):
                self.groups = fetched.sorted { $0.order < $1.order }
            case .failure(let err):
                print("Dashboard groups error:", err)
            }
        }
    }
}
