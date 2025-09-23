import SwiftUI
import FirebaseAuth

struct AddButtonView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ButtonGridViewModel
    let group: String // Group assigned to the new button
    // Optimistic UI callback (parent can insert the new group immediately)
    let onGroupAdded: ((GroupInfo) -> Void)?

    // Tab selection: 0 = Add Button, 1 = Add Group

    init(
        viewModel: ButtonGridViewModel,
        group: String,
        onGroupAdded: ((GroupInfo) -> Void)? = nil
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.group = group
        self.onGroupAdded = onGroupAdded
    }
    @State private var selectedTab: Int = 0

    // Live groups cache for computing next order & validation
    @State private var existingGroups: [GroupInfo] = []

    // New Group fields
    @State private var newGroupName: String = ""
    @State private var newGroupEnabled: Bool = true
    @State private var groupError: String? = nil
    @State private var isSavingGroup: Bool = false

    @State private var name: String = ""
    @State private var cost: String = ""
    @State private var selectedColor: Color = .red
    @State private var selectedImage: String = "1 Strip"
    @State private var availableImages = [
        "1 Strip", "2ct Strip", "3ct Strip", "4ct Strip", "5 Grilled Nugget", "5 Nugget",
        "6ct Cookie", "8ct Grilled Nugget", "8ct Nugget", "10ct Mini", "12 Nugget",
        "12ct Grilled Nugget", "30ct Grilled Nugget", "30ct Nugget", "Apple Juice",
        "Bacon Biscuit", "Bag Filets Breakfast", "Bag Filets", "Bag Grilled Filets",
        "Bag Grilled Nuggets", "Bag Nuggets", "Bag Spicy Breakfast", "Bag Spicy",
        "Bag Strips", "BEC Biscuit", "BEC Muffin", "Biscuit", "Brownie", "Bun",
        "Caramel Crumble Shake", "CEC Muffin", "CFA Biscuit", "CFA Deluxe",
        "CFA Sandwich", "Cherry Berry", "Chicken Bowl", "Chicken Burrito", "Chocolate Milk",
        "Clamshell", "Cobb Salad", "Coke", "Cookie", "Cool Wrap Tray", "Cool Wrap",
        "Diet Coke", "Dressing Apple Cider", "Dressing Avocado Lime",
        "Dressing Balsamic Vinaigrette", "Dressing Cilantro Lime", "Dressing Creamy Salsa",
        "Dressing Honey Mustard", "Dressing Light Italian", "Dressing Ranch", "Egg White",
        "Filet", "Frosted Coffee", "Frosted Lemonade", "Fruit Cup", "Fruit Tray",
        "Grilled Club", "Grilled Filet", "Grilled Sandwich", "Hashbrown", "Honey Packet",
        "Ice Dream Cone", "Kale Tray", "Kale", "Large Fry", "Lemonade Gallon",
        "Lemonade", "Mac & Cheese", "Mac Tray", "Market Salad", "Mayo Packet",
        "Medium Fry", "Milk", "Multigrain Bun", "Noodle Soup", "Nugget Tray",
        "Orange Juice", "Peach Milkshake", "Peppermint Milkshake", "Raw Filet",
        "Raw Nugget", "Raw Spicy", "Salad Tray", "Sauce BBQ", "Sauce Buffalo",
        "Sauce CFA", "Sauce Honey Mustard", "Sauce Honey Roasted", "Sauce Polynesian",
        "Sauce Ranch", "Sauce Sriracha", "Sausage Biscuit", "Sausage Bowl", "Sausage",
        "SEC Biscuit", "SEC Muffin", "Side Salad", "Small Fry", "Spicy Deluxe",
        "Spicy Filet", "Spicy Grilled", "Spicy Sandwich", "Strip Tray", "SW Salad",
        "Sweet Tea Gallon", "Sweet Tea", "Tortilla Soup", "Tortilla", "Waffle Chips",
        "Water Bottle", "Yellow Egg", "Yogurt Parfait"
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - TAB 1: Add Button
            ScrollView {
                VStack(spacing: 16) {
                    // Back Button
                    HStack {
                        Button(action: { dismiss() }) {
                            HStack { Image(systemName: "chevron.left"); Text("Back") }
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.leading)
                        Spacer()
                    }

                    // Title
                    Text("Add New Button")
                        .font(.largeTitle)
                        .bold()
                        .padding(.top)

                    Spacer(minLength: 8)

                    // Name Field
                    VStack(alignment: .leading) {
                        Text("Button Name").font(.headline)
                        TextField("Enter button name", text: $name)
                            .padding()
                            .frame(height: 50)
                            .background(Color(.secondarySystemFill))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .disabled(!Calendar.current.isDateInToday(viewModel.selectedDate))
                    }

                    // Cost Field
                    VStack(alignment: .leading) {
                        Text("Cost").font(.headline)
                        TextField("Enter cost", text: $cost)
                            .keyboardType(.decimalPad)
                            .padding()
                            .frame(height: 50)
                            .background(Color(.secondarySystemFill))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .disabled(!Calendar.current.isDateInToday(viewModel.selectedDate))
                    }

                    // Color Picker
                    VStack(alignment: .leading) {
                        Text("Color").font(.headline)
                        ColorPicker("Select Color", selection: $selectedColor)
                            .padding()
                            .frame(height: 50)
                            .background(Color(.secondarySystemFill))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .disabled(!Calendar.current.isDateInToday(viewModel.selectedDate))
                    }

                    // Image Picker
                    VStack(alignment: .leading) {
                        Text("Image").font(.headline)
                        Picker("Select Image", selection: $selectedImage) {
                            ForEach(availableImages, id: \.self) { imageName in
                                Text(imageName)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding()
                        .frame(height: 50)
                        .background(Color(.secondarySystemFill))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .disabled(!Calendar.current.isDateInToday(viewModel.selectedDate))
                    }

                    // Preview of New Button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview").font(.headline).padding(.horizontal)
                        let previewTallyDate = formatDate(viewModel.selectedDate)
                        let previewButton = ButtonObject(
                            id: UUID().uuidString,
                            image: selectedImage,
                            color: selectedColor.toHexString(),
                            name: name.isEmpty ? "Button Name" : name,
                            cost: Double(cost) ?? 0,
                            tallies: [previewTallyDate: 0],
                            group: group, // Uses selected groupId from parent
                            order: (viewModel.buttons(for: group).map { $0.order }.max() ?? -1) + 1
                        )
                        ButtonView(
                            button: previewButton,
                            selectedDate: viewModel.selectedDate,
                            onTallyIncrement: { _, _ in }
                        )
                        .padding(.horizontal)
                        .disabled(true)
                    }
                    .padding(.bottom, 16)

                    // Save Button
                    Button(action: saveButton) {
                        Text("Save Button")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                    .disabled(name.isEmpty || cost.isEmpty || selectedImage.isEmpty || !Calendar.current.isDateInToday(viewModel.selectedDate))

                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .tag(0)
            .tabItem { Label("Button", systemImage: "square.grid.2x2") }

            // MARK: - TAB 2: Add Group
            ScrollView {
                VStack(spacing: 16) {
                    // Back Button
                    HStack {
                        Button(action: { dismiss() }) {
                            HStack { Image(systemName: "chevron.left"); Text("Back") }
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.leading)
                        Spacer()
                    }

                    // Title
                    Text("Add New Group")
                        .font(.largeTitle)
                        .bold()
                        .padding(.top)

                    // Helpful note
                    Text("Group name will also be used as the Firestore doc id (e.g., \"Lunch\").")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Group Name
                    VStack(alignment: .leading) {
                        Text("Group Name").font(.headline)
                        TextField("e.g., Lunch", text: $newGroupName)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding()
                            .frame(height: 50)
                            .background(Color(.secondarySystemFill))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }

                    // Enabled toggle
                    Toggle(isOn: $newGroupEnabled) {
                        Text("Enabled")
                    }
                    .padding(.horizontal)

                    // Computed next order
                    HStack {
                        Text("Next order:")
                        Text(String((existingGroups.map { $0.order }.max() ?? -1) + 1))
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal)

                    if let groupError { Text(groupError).foregroundColor(.red).padding(.horizontal) }

                    Button(action: saveGroup) {
                        HStack {
                            if isSavingGroup { ProgressView().padding(.trailing, 6) }
                            Text("Save Group")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .background(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingGroup)

                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .tag(1)
            .tabItem { Label("Group", systemImage: "folder.badge.plus") }
        }
        .onAppear { loadExistingGroups() }
    }

    // MARK: - Save Group Action
    private func saveGroup() {
        groupError = nil
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let nextOrder = (existingGroups.map { $0.order }.max() ?? -1) + 1
        let info = GroupInfo(
            id: trimmed,
            title: trimmed,
            icon: nil,
            order: nextOrder,
            isEnabled: newGroupEnabled,
            timestamp: nil
        )

        // --- Optimistic UI update ---
        onGroupAdded?(info)
        existingGroups.append(info)
        existingGroups.sort { $0.order < $1.order }
        // Selectively dismiss so parent can refresh its tabs immediately
        dismiss()

        let storeId = Auth.auth().currentUser?.uid ?? "UnknownUser"
        isSavingGroup = true
        Task {
            do {
                try await FirebaseService.shared.upsertGroup(info, forUserId: storeId)
                // Refresh local cache in the background for correctness (parent already optimistically updated)
                if let fetched = try? await FirebaseService.shared.fetchGroups(forUserId: storeId, includeDisabled: true) {
                    existingGroups = fetched
                }
                // No dismiss here: we already dismissed optimistically
            } catch {
                groupError = error.localizedDescription
                isSavingGroup = false
            }
        }
    }

    // MARK: - Load existing groups (for order + validation)
    private func loadExistingGroups() {
        let storeId = Auth.auth().currentUser?.uid ?? "UnknownUser"
        Task {
            if let fetched = try? await FirebaseService.shared.fetchGroups(forUserId: storeId, includeDisabled: true) {
                existingGroups = fetched
            }
        }
    }

    // MARK: - Save Button Action
    private func saveButton() {
        guard let costValue = Double(cost), !name.isEmpty else {
            return
        }

        // Convert Color to Hex String
        let colorString = selectedColor.toHexString()
        let formattedDate = formatDate(viewModel.selectedDate) // Convert date to string

        // Determine the new button's order
        let newOrder = (viewModel.buttons(for: group).map { $0.order }.max() ?? -1) + 1

        // Create the ButtonObject with date-based tally tracking
        let newButton = ButtonObject(
            id: UUID().uuidString,      // Unique identifier
            image: selectedImage,       // Image name
            color: colorString,         // Hex color string
            name: name,                 // Button name
            cost: costValue,            // Button cost as Double
            tallies: [formattedDate: 0], // Default tally for selected date
            group: group,               // Group set from the parent view
            order: newOrder             // New order value
        )

        Task {
            await viewModel.addButton(newButton)
            dismiss()
        }
    }

    // MARK: - Date Formatting
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Color Conversion Extension
extension Color {
    func toHexString() -> String {
        let components = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
