import SwiftUI

struct RadialView: View {
    @Environment(\.presentationMode) var presentationMode
    let button: ButtonObject
    let selectedDate: Date // ✅ Selected date passed in
    let onIncrement: (Int, Date) -> Void // ✅ Updates correct date
    let onDelete: () -> Void // Callback for deletion
    let availableImages: [String]
    let availableGroups: [String]
    let onSave: (ButtonObject) -> Void

    @State private var isNegativeMode = false // Toggle positive/negative mode
    @State private var showDeleteConfirmation = false
    @State private var isShowingEdit = false
    @State private var editPulse = false

    var body: some View {
        ZStack {
            // Transparent Background to Dismiss
            Color.clear
                .ignoresSafeArea()
                .onTapGesture {
                    presentationMode.wrappedValue.dismiss() // Dismiss on tap
                }

            VStack(spacing: 16) {
                // White Circular Background
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 250, height: 250)

                    // Toggle Button in Center
                    Button(action: {
                        isNegativeMode.toggle()
                    }) {
                        Text(isNegativeMode ? "Negative" : "Positive")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding()
                            .background(
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 100, height: 100)
                            )
                    }

                    // Radial Action Buttons
                    let increments = [5, 20, 50, 100, 200]

                    ForEach(0..<6) { index in
                        Button(action: {
                            if index == 0 {
                                // Show confirmation instead of direct delete
                                showDeleteConfirmation = true
                            } else {
                                let value = isNegativeMode ? -increments[index - 1] : increments[index - 1]
                                onIncrement(value, selectedDate)
                                presentationMode.wrappedValue.dismiss()
                            }
                        }) {
                            Circle()
                                .fill(index == 0 ? Color.red : Color.blue)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text(index == 0 ? "Del" : "\(isNegativeMode ? "-" : "+")\(increments[index - 1])")
                                        .foregroundColor(.white)
                                        .bold()
                                )
                        }
                        .offset(radialOffset(index: index, radius: 110, totalButtons: 6))
                    }
                }

                // Edit Button (bigger, offset down+left, more prominent)
                Button(action: {
                    isShowingEdit = true
                }) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 68, height: 68)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            )
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        Text("Edit")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                    }
                }
                .offset(y: 80)
                .scaleEffect(editPulse ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: editPulse)
                .accessibilityLabel("Edit Button")
                .onAppear { editPulse = true }
            }
        }
        .alert("Are you sure you want to delete this button?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
                presentationMode.wrappedValue.dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
        .sheet(isPresented: $isShowingEdit) {
            EditView(
                button: .constant(button),
                isPresented: $isShowingEdit,
                onSave: onSave
            )
        }
    }

    // MARK: - Helper for Radial Layout
    private func radialOffset(index: Int, radius: CGFloat, totalButtons: Int) -> CGSize {
        let angle = Angle.degrees(Double(index) * 360.0 / Double(totalButtons) - 90)
        return CGSize(
            width: cos(CGFloat(angle.radians)) * radius,
            height: sin(CGFloat(angle.radians)) * radius
        )
    }
}

#Preview {
    RadialView(
        button: ButtonObject(
            id: "testButton",
            image: "cart",
            color: "blue",
            name: "Test Button",
            cost: 5.99,
            tallies: ["2024-01-15": 0], // Example date-based tracking
            group: "FOH",
            order: 1
        ),
        selectedDate: Date(), // ✅ Pass selected date
        onIncrement: { increment, date in
            print("Incremented by \(increment) on \(date)")
        },
        onDelete: {
            print("Button Deleted")
        },
        availableImages: ["cart", "star", "heart"], 
        availableGroups: ["FOH", "BOH", "Management"],
        onSave: { updatedButton in
            print("Saved button: \(updatedButton)")
        }
    )
}
