//
//  RootView.swift
//  CFA Waste
//
//  Created by Boyd Emmons on 9/23/24.
//

import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase  // allows the view to detect app states, active, inactive, and background
    @EnvironmentObject var buttonGridVM: ButtonGridViewModel  // Pulls in the buttongridviewmodel to fetch buttons on appear
    @EnvironmentObject var authViewModel: AuthViewModel  // authentication view model to pass into other views
    var body: some View {
        NavigationStack {
            if authViewModel.isAuthenticated {  // If authenticated with the authviewmodel
                if UIDevice.current.userInterfaceIdiom == .phone {  // if phone, graph
                    GraphView()
                        .environmentObject(GraphViewModel(userId: authViewModel.userId ?? ""))
                } else {  // else home
                    HomeView()
                }
            } else {  // if not authenticated
                SignInEmailView()
            }
        }
        .onAppear { // Fetches the buttons as soon as the app opens and passes it to whichever view is active
            Task {
                await buttonGridVM.fetchButtons(for: buttonGridVM.selectedDate)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in // iOS 17+: two-parameter action closure
            if newPhase == .active || newPhase == .background {
                Task { await buttonGridVM.flushPendingSyncs() }
            }
        }
    }
}
