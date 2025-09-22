import SwiftUI

struct FOHView: View {
    @ObservedObject var viewModel: ButtonGridViewModel
    @Binding var isMoving: Bool
    let selectedDate: Date // ✅ Accept selectedDate as a parameter

    var body: some View {
        VStack {
            ButtonGridView(viewModel: viewModel, group: "FOH", isMoving: $isMoving, selectedDate: selectedDate) // ✅ Pass selectedDate
        }
        .onAppear {
            Task {
                await viewModel.fetchButtons(for: selectedDate) // ✅ Ensure correct date data is fetched
            }
        }
    }
}

#Preview {
    FOHView(viewModel: ButtonGridViewModel(), isMoving: .constant(false), selectedDate: Date()) // ✅ Added selectedDate
}
