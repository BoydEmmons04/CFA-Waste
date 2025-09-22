import SwiftUI

struct BreakfastView: View {
    @ObservedObject var viewModel: ButtonGridViewModel // Shared ViewModel for button management
    @Binding var isMoving: Bool // Control for reordering state
    let selectedDate: Date // ✅ Pass selectedDate to ensure correct tallies

    var body: some View {
        ButtonGridView(viewModel: viewModel, group: "Breakfast", isMoving: $isMoving, selectedDate: selectedDate) // ✅ Pass selectedDate
    }
}

#Preview {
    BreakfastView(viewModel: ButtonGridViewModel(), isMoving: .constant(false), selectedDate: Date()) // ✅ Ensure preview works with a date
}
