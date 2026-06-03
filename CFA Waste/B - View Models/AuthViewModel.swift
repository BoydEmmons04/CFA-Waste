import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String? = nil

    /// Creates default, non-sensitive account documents under users/{uid}/account/
    /// - Documents: "Name" (String value), "Number" (Int value), "TopBannerSetting" (String value: "default")
    private func createDefaultAccountDocuments(for uid: String, pin: String) async throws {
        let db = Firestore.firestore()
        let account = db.collection("users").document(uid).collection("account")

        // Coerce the PIN to Int for the Number document
        let pinInt = Int(pin) ?? 0

        try await account.document("Name").setData(["value": ""], merge: true)
        try await account.document("Number").setData(["value": pinInt], merge: true)
        try await account.document("TopBannerSetting").setData(["value": "default"], merge: true)
    }

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
            // Create default non-sensitive account documents
            try await createDefaultAccountDocuments(for: currentUser.uid, pin: pin)
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
