import SwiftUI

struct LunchView: View {
    @ObservedObject var viewModel: ButtonGridViewModel // Shared ViewModel for button management
    @Binding var isMoving: Bool // Control for reordering state
    let selectedDate: Date // ✅ Pass selectedDate to ensure correct tallies

    var body: some View {
        ButtonGridView(viewModel: viewModel, group: "Lunch", isMoving: $isMoving, selectedDate: selectedDate) // ✅ Pass selectedDate
    }
}

#Preview {
    LunchView(viewModel: ButtonGridViewModel(), isMoving: .constant(false), selectedDate: Date()) // ✅ Ensure preview works with a date
}
//test
