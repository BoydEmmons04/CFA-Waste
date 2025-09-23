import SwiftUI
import UIKit

// Hard-coded list of images for the picker
let defaultAvailableImages = [
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

// Hard-coded list of groups for the picker
let defaultAvailableGroups = ["FOH", "BOH", "Breakfast", "Lunch", "Raw", "Prep"]

struct EditView: View {
    @Binding var button: ButtonObject
    @Binding var isPresented: Bool
    let onSave: (ButtonObject) -> Void

    @State private var name: String
    @State private var cost: String
    @State private var selectedImage: String
    @State private var selectedColor: Color
    @State private var selectedGroup: String

    // Optional dynamic groups provided by parent (e.g., RadialView / ButtonGridView)
    let availableGroups: [GroupInfo]?

    init(button: Binding<ButtonObject>,
         isPresented: Binding<Bool>,
         availableGroups: [GroupInfo]? = nil,
         onSave: @escaping (ButtonObject) -> Void) {
        self._button = button
        self._isPresented = isPresented
        self.onSave = onSave

        let b = button.wrappedValue
        _name = State(initialValue: b.name)
        _cost = State(initialValue: String(format: "%.2f", b.cost))
        _selectedImage = State(initialValue: b.image)
        _selectedColor = State(initialValue: Self.colorFromString(b.color))
        _selectedGroup = State(initialValue: b.group)
        self.availableGroups = availableGroups
    }

    // Parse cost text into a Double, allowing "$" and commas
    private func parseCost(_ input: String, fallback: Double) -> Double {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
        return Double(cleaned) ?? fallback
    }

    // Merge defaults with current image so the picker always includes what's already saved
    private var allImages: [String] {
        Array(Set(defaultAvailableImages + [button.image, selectedImage])).sorted()
    }

    // Convert stored string (named color or hex like "#RRGGBB") into Color
    private static func colorFromString(_ hexOrName: String) -> Color {
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
        // Fall back to system/asset color names
        return Color(hexOrName)
    }

    // Convert Color to hex string #RRGGBB (used for persistence)
    private static func colorToHex(_ color: Color) -> String {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(r * 255), gi = Int(g * 255), bi = Int(b * 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #else
        return "#000000"
        #endif
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Button Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Button Name")
                        .font(.headline)
                    TextField("Enter name", text: $name)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                }
                .padding(.horizontal)

                // Cost
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cost")
                        .font(.headline)
                    TextField("0.00", text: $cost)
                        .keyboardType(.decimalPad)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                }
                .padding(.horizontal)

                // Image Picker (menu-style, includes any existing custom value)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Image")
                        .font(.headline)
                    Picker("Select Image", selection: $selectedImage) {
                        ForEach(allImages, id: \.self) { img in
                            Text(img).tag(img)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                }
                .padding(.horizontal)

                // Color Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color")
                        .font(.headline)
                    ColorPicker("", selection: $selectedColor)
                        .labelsHidden()
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                }
                .padding(.horizontal)

                // Live Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.08))
                        ButtonView(
                            button: ButtonObject(
                                id: button.id,
                                image: selectedImage,
                                color: Self.colorToHex(selectedColor),
                                name: name.isEmpty ? button.name : name,
                                cost: parseCost(cost, fallback: button.cost),
                                tallies: button.tallies,
                                group: selectedGroup,
                                order: button.order
                            ),
                            selectedDate: Date(),
                            onTallyIncrement: { _, _ in }
                        )
                        .padding(12)
                    }
                    .frame(height: 160)
                    .shadow(radius: 1)
                }
                .padding(.horizontal)

                Spacer()

                // Actions
                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))
                            .foregroundColor(.primary)
                    }

                    Button(action: {
                        let updated = ButtonObject(
                            id: button.id,
                            image: selectedImage,
                            color: Self.colorToHex(selectedColor),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            cost: parseCost(cost, fallback: button.cost),
                            tallies: button.tallies,
                            group: selectedGroup,
                            order: button.order
                        )
                        onSave(updated)          // Persist via ViewModel in parent
                        button = updated         // Update local binding so UI reflects changes immediately
                        isPresented = false
                    }) {
                        Text("Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                            .foregroundColor(.white)
                    }
                    .disabled(name.isEmpty || cost.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .padding(.top, 16)
        }
    }
}

struct EditView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = ButtonObject(
            id: "1",
            image: "cart",
            color: "blue",
            name: "Sample",
            cost: 2.50,
            tallies: ["2025-07-01": 3],
            group: "FOH",
            order: 1
        )
        return EditView(
            button: .constant(sample),
            isPresented: .constant(true),
            onSave: { _ in }
        )
    }
}
