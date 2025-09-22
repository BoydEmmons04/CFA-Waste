import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(userId: String) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(userId: userId))
    }

    private let groups = ["FOH", "Shared Table", "Breakfast", "Lunch", "Raw", "Prep"]

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
                } else {
                    List {
                        ForEach(groups, id: \.self) { group in
                            let formattedDate = Self.dateFormatter.string(from: viewModel.selectedDate)
                            
                            let totalForGroup = viewModel.buttonObjects
                                .filter { $0.group == group }
                                .map { viewModel.getTotalCost(for: $0, on: formattedDate) }
                                .reduce(0, +)
                            
                            let sortedButtons = viewModel.buttonObjects
                                .filter { $0.group == group }
                                .sorted {
                                    viewModel.getTotalCost(for: $0, on: formattedDate) >
                                    viewModel.getTotalCost(for: $1, on: formattedDate)
                                }
                            
                            if !sortedButtons.isEmpty {
                                Section(header:
                                    HStack {
                                        Text(group)
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
                Task {
                    await viewModel.loadButtonObjects(for: viewModel.selectedDate)
                    await viewModel.loadWeeklyData(relativeTo: viewModel.selectedDate)
                }
            }
        }
    }
}
