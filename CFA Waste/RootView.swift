//
//  RootView.swift
//  CFA Waste
//
//  Created by Boyd Emmons on 9/23/24.
//

import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var buttonGridVM: ButtonGridViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    var body: some View {
        NavigationStack {
            if authViewModel.isAuthenticated {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    GraphView()
                        .environmentObject(GraphViewModel(userId: authViewModel.userId ?? ""))
                } else {
                    HomeView()
                }
            } else {
                SignInEmailView()
            }
        }
        .onAppear {
            Task {
                await buttonGridVM.fetchButtons(for: buttonGridVM.selectedDate)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active || newPhase == .background {
                Task { await buttonGridVM.flushPendingSyncs() }
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
        .environmentObject(ButtonGridViewModel())
}
