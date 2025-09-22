import Foundation
import FirebaseAuth

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String? = nil

    init() {
        // Automatically listen for authentication changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isAuthenticated = user != nil
            self?.userId = user?.uid
        }
    }

    func logIn(pin: String) async throws {
        let _ = try await AuthenticationManager.shared.signIn(pin: pin)

        // Wait briefly to ensure Firebase updates before checking user ID
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        if let currentUser = Auth.auth().currentUser {
            userId = currentUser.uid
        }
    }

    func register(pin: String) async throws {
        let _ = try await AuthenticationManager.shared.createUser(pin: pin)

        // Wait briefly to ensure Firebase updates before checking user ID
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        if let currentUser = Auth.auth().currentUser {
            userId = currentUser.uid
        }
    }

    func signOut() {
        do {
            try AuthenticationManager.shared.signOut()
            isAuthenticated = false
            userId = nil
        } catch {
            print("Failed to sign out: \(error.localizedDescription)")
        }
    }
}
