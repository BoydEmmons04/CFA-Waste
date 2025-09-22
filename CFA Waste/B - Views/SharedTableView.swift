import SwiftUI

struct SharedTableView: View {
    @ObservedObject var viewModel: ButtonGridViewModel // Shared ViewModel for button management
    @Binding var isMoving: Bool // Control for reordering state
    let selectedDate: Date // ✅ Pass selectedDate to ensure correct tallies

    var body: some View {
        ButtonGridView(viewModel: viewModel, group: "Shared Table", isMoving: $isMoving, selectedDate: selectedDate) // ✅ Pass selectedDate
    }
}

#Preview {
    SharedTableView(viewModel: ButtonGridViewModel(), isMoving: .constant(false), selectedDate: Date()) // ✅ Ensure preview works with a date
}
