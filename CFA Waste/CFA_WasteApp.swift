import SwiftUI
import Firebase

@main
struct CFA_WasteApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var buttonGridVM = ButtonGridViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(buttonGridVM)
        }
    }
}
