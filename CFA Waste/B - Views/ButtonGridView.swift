import SwiftUI

struct ButtonGridView: View {
    @ObservedObject var viewModel: ButtonGridViewModel
    let group: String
    @Binding var isMoving: Bool
    let selectedDate: Date // Pass selected date to update displayed tallies
    let availableGroups: [GroupInfo]

    @State private var selectedButton: ButtonObject?
    @State private var showRadialView = false
    @State private var radialScale: CGFloat = 0.5
    @State private var lastTapTime: Date = .distantPast
    @State private var isLongPressActive = false
    @State private var isIncrementing = false // Prevent duplicate increments
    @State private var shakePhase: CGFloat = 0
    @State private var lockPulse: Bool = false

    var body: some View {
        GeometryReader { geometry in
            // Determine if the device is in landscape mode
            let isLandscape = geometry.size.width > geometry.size.height
            let columnsCount = isLandscape ? 4 : 3
            let rowsPerPage = isLandscape ? 3 : 4
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnsCount)
            // Set vertical spacing: 60 in portrait, 30 in landscape (50% less)
            let verticalSpacing: CGFloat = isLandscape ? 30 : 60
            
            ZStack {
                VStack {
                    if isMoving {
                        List {
                            ForEach(viewModel.buttons(for: group), id: \.id) { button in
                                Text(button.name)
                            }
                            .onMove { source, destination in
                                Task {
                                    await viewModel.reorderButtons(from: source, to: destination, in: group)
                                }
                            }
                        }
                        .environment(\.editMode, .constant(.active))
                    } else {
                        // Paginate buttons based on the current grid size.
                        let pages = paginateButtons(viewModel.buttons(for: group), rowsPerPage: rowsPerPage, columnsCount: columnsCount)
                        TabView {
                            ForEach(Array(pages.enumerated()), id: \.offset) { (_, pageButtons) in
                                LazyVGrid(columns: gridColumns, spacing: verticalSpacing) {
                                    ForEach(pageButtons) { button in
                                        ButtonView(button: button, selectedDate: selectedDate) { pressedButton, date in
                                            handleButtonPress(pressedButton, date: date)
                                        }
                                        .disabled(!Calendar.current.isDateInToday(selectedDate))
                                        // Attach gestures: drag has higher priority than long press.
                                        .highPriorityGesture(createDragGesture(for: button))
                                        .gesture(createLongPressGesture(for: button))
                                    }
                                }
                                .padding()
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    }
                }
                
                // Lock overlay when viewing a past date — with shake + hint to use Date Picker
                if !Calendar.current.isDateInToday(selectedDate) && !showRadialView {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()

                    VStack(spacing: 10) {
                        // Hint banner
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                            Text("Viewing past date")
                                .font(.headline)
                            Text("Change the date above to edit")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.35))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15)))
                        )

                        // Nudging arrow pointing up
                        Image(systemName: "arrow.up")
                            .font(.title2)
                            .opacity(lockPulse ? 1.0 : 0.6)
                            .scaleEffect(lockPulse ? 1.1 : 0.95)
                            .animation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: lockPulse)
                    }
                    .foregroundColor(.white)
                    .padding(.top, 30)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .onAppear {
                        // Start subtle pulse for arrow and shake for lock icon
                        lockPulse = true
                        withAnimation(Animation.linear(duration: 0.6).repeatForever(autoreverses: true)) {
                            shakePhase = 1
                        }
                    }

                    // Shaking lock icon
                    Image(systemName: "lock.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(.white)
                        .modifier(ShakeEffect(animatableData: shakePhase))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                
                // If the RadialView is shown, overlay it
                if showRadialView, let button = selectedButton {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showRadialView = false
                                isLongPressActive = false
                            }
                        }
                    
                    RadialView(
                        button: button,
                        selectedDate: selectedDate,
                        onIncrement: { increment, date in
                            Task {
                                await incrementTally(button, by: increment, date: date)
                                showRadialView = false
                                isLongPressActive = false
                            }
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteButton(button)
                                showRadialView = false
                                isLongPressActive = false
                            }
                        },
                        availableImages: defaultAvailableImages,
                        availableGroups: availableGroups,
                        onSave: { updatedButton in
                            Task {
                                await viewModel.updateButton(updatedButton)
                            }
                            withAnimation {
                                showRadialView = false
                                isLongPressActive = false
                            }
                        }
                    )
                    .scaleEffect(radialScale)
                    .onAppear {
                        withAnimation(.spring()) { radialScale = 1.0 }
                    }
                    .onDisappear {
                        radialScale = 0.5
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            viewModel.bind(groupId: group, date: selectedDate)
        }
        .onChange(of: selectedDate) { newDate in
            viewModel.bind(groupId: group, date: newDate)
        }
        .onChange(of: group) { newGroup in
            viewModel.bind(groupId: newGroup, date: selectedDate)
        }
    }
    
    // MARK: - Handle Button Press
    private func handleButtonPress(_ button: ButtonObject, date: Date) {
        guard Calendar.current.isDateInToday(date) else { return }
        guard !showRadialView, !isIncrementing else {
            print("Button press ignored while radial view is active or incrementing")
            return
        }
        
        let now = Date()
        guard now.timeIntervalSince(lastTapTime) > 0.001 else {
            print("Ignored tap due to debounce")
            return
        }
        lastTapTime = now
        isIncrementing = true
        
        // Optimistic tally + background sync via ViewModel
        Task {
            await viewModel.incrementTally(for: button, by: 1, date: date)
            isIncrementing = false
        }
    }
    
    // MARK: - Increment/Decrement Tally
    private func incrementTally(_ button: ButtonObject, by amount: Int, date: Date) async {
        await viewModel.incrementTally(for: button, by: amount, date: date)
    }
    
    // MARK: - Handle Long Press
    private func handleLongPress(_ button: ButtonObject) {
        guard Calendar.current.isDateInToday(selectedDate) else { return }
        print("Long press detected on button: \(button.name)")
        isLongPressActive = true
        selectedButton = button
        withAnimation(.spring()) {
            showRadialView = true
        }
    }
    
    // MARK: - Create Long Press Gesture
    private func createLongPressGesture(for button: ButtonObject) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                if !isLongPressActive {
                    handleLongPress(button)
                }
            }
    }
    
    // MARK: - Create Drag Gesture for Swipe Down
    private func createDragGesture(for button: ButtonObject) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.height > 20,
                      Calendar.current.isDateInToday(selectedDate) else { return }
                Task {
                    await incrementTally(button, by: -1, date: selectedDate)
                }
            }
    }
    
    // MARK: - Paginate Buttons
    private func paginateButtons(_ buttons: [ButtonObject], rowsPerPage: Int, columnsCount: Int) -> [[ButtonObject]] {
        let buttonsPerPage = rowsPerPage * columnsCount
        return stride(from: 0, to: buttons.count, by: buttonsPerPage).map {
            Array(buttons[$0..<min($0 + buttonsPerPage, buttons.count)])
        }
    }
}

// MARK: - ShakeEffect
fileprivate struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
