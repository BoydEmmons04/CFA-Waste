import SwiftUI
import Firebase

@main  // defines this view to run first before anything else
struct CFA_WasteApp: App {
    @StateObject private var authViewModel = AuthViewModel()  // initializes the view models on open
    @StateObject private var buttonGridVM = ButtonGridViewModel()

    init() {  // Calls the firebase api to configure
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup { // defines the scene for all other views to go in
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(buttonGridVM)
        }
    }
}
