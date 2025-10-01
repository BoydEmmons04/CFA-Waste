import SwiftUI

// @State tells the compiler to allocate designated memory for a variable outside the scope of the view
// private makes sure that only this view can use the values
// @Namespace is a shared "animation playground" defines categoryNS as an id that can be shared by multiple items. this allows them to morph and transition between each other
// @EnvironmentObject declares the viewmodels to be used in other files
struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel  // Connects the HomeView to the Authentication service model
    @EnvironmentObject var buttonViewModel: ButtonGridViewModel  // Connects to the ButtonGridViewModel
    @State private var selectedView: String = ""  // Selected View is stored as a string
    @State private var isShowingAddButtonView = false   // Trigger for the add button
    @State private var isMovingButtons = false  // Trigger for moving buttons view
    @State private var isShowingSignOutAlert = false // Trigger for showing the sign out confirm
    @Namespace private var categoryNS  // see above

    @State private var groups: [GroupInfo] = [] // an array to store groupinfo in

    // Dynamic items sourced from Firestore groups
    private var categoryItems: [(key: String, label: String)] { // defines the categoryitems list struct
        groups.map { ($0.id, $0.title) }
    }

    var body: some View {  // defines the body of the view
        NavigationStack {   // defines a navigation stack with toolbar at the top. This also allows for the display of other views on top with a default back button
            VStack {  // A vertical stack of elements
                if let current = groups.first(where: { $0.id == selectedView }) { // Go through the list of groups until you get to the first one whos id = selected id
                    // This instantiates the View object within the GroupsHostView
                    DynamicGroupView(    // Generates a dynamic view using the groups host view
                        buttonGridVM: buttonViewModel,
                        groupId: current.id,
                        isMoving: $isMovingButtons,
                        selectedDate: buttonViewModel.selectedDate,
                        availableGroups: groups
                    )
                } else {  // If a group was not found that matches the selectedViewId
                    VStack(spacing: 12) {   // Creates a vstack that has 12 spacing between members
                        if groups.isEmpty {  // If there are no groups
                            ProgressView()     // Load the progress view
                            Text("Loading groups…").foregroundColor(.secondary) // Puts text under the progress view saying loading groups
                        } else { // if there are groups but none selected
                            Text("Select a group").foregroundColor(.secondary) // Asks user to select a group
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)  //grow the vstack as much as the vstack will allow
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // Grow the vstack as much as the navigation stack will allow
            .navigationTitle(" ") // ✅ Force toolbar to appear
            .navigationBarTitleDisplayMode(.inline) // Forces the title of the navigationbar to be inline

        }
        .toolbar {      // Defines a toolbar outside the navigation stack
            // Sign Out Button (Leading)
            ToolbarItem(placement: .navigationBarLeading) {  // Defines a toolbar item that is leading
                Button(action: {     // Creates a button that toggles the sign out alert bool
                    isShowingSignOutAlert = true
                }) {        // Defined as the text sign out and the color red
                    Text("Sign Out")
                        .foregroundColor(.red)
                }
            }

            // Centered Date Picker in Toolbar
            ToolbarItem(placement: .principal) {
                DatePicker("", selection: $buttonViewModel.selectedDate, displayedComponents: .date)// Binds the DatePickers output to the viewModel Selected Date. displays date
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            // Add & Move Buttons (Trailing)
            ToolbarItemGroup(placement: .navigationBarTrailing) {  // Trailing add button
                Button(action: {
                    isShowingAddButtonView = true // toggles the addview when pressed
                }) {
                    Image(systemName: "plus")  // sets the button to a blue plus
                        .font(.title2)
                }
                .disabled(!DateAuthority.isDeviceToday(buttonViewModel.selectedDate)) // Disables the add button if the selected date is not "today"

                Button(action: {  //Button for changing order of buttons
                    isMovingButtons.toggle()
                }) {
                    Image(systemName: isMovingButtons ? "checkmark" : "arrow.up.arrow.down.circle")
                        .font(.title2)
                }

                // Only show "Graph View" button on iPad
                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationLink("Graph View") {
                        GraphView()
                        // pass in environment objects (view models)
                            .environmentObject(authViewModel)
                            .environmentObject(buttonViewModel)
                    }
                }
            }
        }
        .alert("Confirm Sign Out", isPresented: $isShowingSignOutAlert) {   // Defines an alert that triggers when the sign out button is pressed
            Button("Sign Out", role: .destructive) {  // Defines sign out as a destructive button that makes a change
                authViewModel.signOut()  // calls sign out from the viewmodel
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .sheet(isPresented: $isShowingAddButtonView) {  // Present a sheet when var is true
            AddButtonView(  // Defines the sheet as the AddButtonView
                viewModel: buttonViewModel,
                group: selectedView,
                onGroupAdded: { newGroup in
                    if let idx = groups.firstIndex(where: { $0.id == newGroup.id }) {  // If group already exists, merge
                        groups[idx] = newGroup
                    } else {  // If not, add
                        groups.append(newGroup)
                    }
                    groups.sort { $0.order < $1.order }  // Sort the group in order defined [TO DO SORTING]
                    selectedView = newGroup.id  // Sets the selected group to the new one
                }
            )
        }
        .safeAreaInset(edge: .bottom) {  // Insets the bar at the bottom of the screen to account for ios gestures
            AppStoreCategoryPicker(  // Make an object at the bottom that uses the struct AppStoreCategoryPicker
                items: categoryItems,
                selection: $selectedView,
                ns: categoryNS
            )
            .padding(.bottom, 8)  // Add more padding at the bottom
        }
        .onAppear {  // On start, storeId = userid or unknownuser
            let storeId = authViewModel.userId ?? "UnknownUser"
            FirebaseService.shared.listenGroups(forUserId: storeId, includeDisabled: false) { result in  // pull from firestore the id
                switch result {
                case .success(let fetched):  // If items are found in group, listen to the items for changes in the group
                    self.groups = fetched
                    if self.selectedView.isEmpty, let first = fetched.first { self.selectedView = first.id }
                case .failure(let err):  // If the fetch fails, log
                    print("Groups listen error:", err)
                }
            }
        }
        .onDisappear {  // On group selection change, stop listening to the previous group
            FirebaseService.shared.stopGroups()
        }
        
    }
}

// MARK: - App Store–style Liquid Glass Category Picker
fileprivate struct AppStoreCategoryPicker: View {  // Defines a new view that is only visible from this view
    let items: [(key: String, label: String)]  // there are items that have a key and label
    @Binding var selection: String  // currently selected key
    var ns: Namespace.ID  // A matched geometry namespace not implemented completely
    @State private var contentWidth: CGFloat = 0 // Stores the content width so content can be centered when the list is narrower thatn the screen

    var body: some View {
        ZStack {
            // Glassy background bar
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            GeometryReader { geo in
                let inset = max(0, (geo.size.width - contentWidth) / 2)  // Reads the size x, y of the current group and defines an inset width for it
                ScrollView(.horizontal, showsIndicators: false) {  // left and right scroll view
                    HStack(spacing: 8) {  // spacing of 8 between buttons
                        ForEach(items, id: \.key) { item in  //  iterates through each "item" (group
                            let isSelected = item.key == selection
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {  //  defines the animation easing and damping
                                    selection = item.key  // defines the end goal of the move
                                }
                            } label: {  // Adds the label over the liquid glass
                                Text(item.label)  // Uses selected groups label to overlay
                                    .font(.callout)  // Font bold
                                    .fontWeight(isSelected ? .semibold : .regular)  // bold
                                    .padding(.horizontal, 16)  // padding
                                    .padding(.vertical, 10)
                                    .background(Color.clear)  // clear background behind the text
                                    .contentShape(Rectangle())  // button is a rectangle
                                    .anchorPreference(key: ChipFramesKey.self, value: .bounds) { [item.key: $0] }  //  attaches an anchor into a dictionary indexed by the groups key. used later
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(WidthMeasurer())  // Makes the background the correct width
                    .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }  // Helper for when the selected group is changed
                    .padding(.vertical, 8)
                    .padding(.leading, inset + 8)
                    .padding(.trailing, inset + 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))  // makes sure everything respects the rounded corners of the bounding box
            }
            .overlayPreferenceValue(ChipFramesKey.self) { prefs in  // reads dictionary of chip anchors (coords to start at in the center of each group label)
                GeometryReader { proxy in  // Converts the anchor into actual coords
                    if let anchor = prefs[selection] {
                        let rect = proxy[anchor]
                        Capsule()   // draws the capsuel around the selected group
                            .stroke(
                                LinearGradient(     // top left to bottom right gradient
                                    colors: [
                                        Color.blue.opacity(0.85),
                                        Color.white.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3  // stroke width of the outline on the buttons
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)  // makes sure that the buttons are still pressable even with the capsule overlay
                            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selection)  // defines the animation of the capsule moving
                    }
                }
            }
        }
        .frame(height: 88)
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }
}

// MARK: - Width Measuring Helpers
fileprivate struct WidthMeasurer: View {  // Returns a views width
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentWidthKey.self, value: proxy.size.width)
        }
    }
}

fileprivate struct ContentWidthKey: PreferenceKey {  //  Takes the max width
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

fileprivate struct ChipFramesKey: PreferenceKey {  
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
