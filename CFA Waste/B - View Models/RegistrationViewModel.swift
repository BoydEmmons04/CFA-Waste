import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class RegistrationViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var pin: String = ""
    @Published var confirmPin: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""

    var isInputValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDigits = pin.allSatisfy { $0.isNumber }
        return !trimmedName.isEmpty && isDigits && pin.count == 5 && pin == confirmPin
    }

    func register() {
        guard isInputValid else {
            if pin != confirmPin { errorMessage = "PINs do not match." }
            else if pin.count != 5 || !pin.allSatisfy({ $0.isNumber }) { errorMessage = "PIN must be 5 digits." }
            else if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errorMessage = "Name is required." }
            else { errorMessage = "Please check your inputs." }
            return
        }
        
        Task {
            // Start loading
            await MainActor.run {
                isLoading = true
                errorMessage = ""
            }
            
            do {
                let _ = try await AuthenticationManager.shared.createUser(pin: pin)
                // Resolve UID from Auth; create default account docs
                guard let uid = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "Registration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user UID after registration."])
                }
                try await createDefaultAccountDocuments(for: uid, pin: pin, name: name)
                print("User registered and account defaults created for uid=\(uid)")
            } catch {
                let message = handleError(error)
                await MainActor.run {
                    errorMessage = message
                }
            }
            
            // Stop loading
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func handleError(_ error: Error) -> String {
        if let authError = error as NSError?, let errorCode = AuthErrorCode(rawValue: authError.code) {
            switch errorCode {
            case .emailAlreadyInUse:
                return "PIN is already registered."
            default:
                return "Registration failed: \(error.localizedDescription)"
            }
        }
        return "An unexpected error occurred. Please try again."
    }

    /// Creates default, non-sensitive account documents under users/{uid}/account/
    /// - Documents created: "Name" (string, value: provided name), "Number" (int, value: PIN), "TopBannerSetting" (string, value: "default")
    private func createDefaultAccountDocuments(for uid: String, pin: String, name: String) async throws {
        let db = Firestore.firestore()
        let account = db.collection("users").document(uid).collection("account")

        // Coerce PIN to Int per requirement; fallback to 0 if not numeric
        let pinInt = Int(pin) ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create/merge the three docs
        try await account.document("Name").setData(["value": trimmedName], merge: true)
        try await account.document("Number").setData(["value": pinInt], merge: true)
        try await account.document("TopBannerSetting").setData(["value": "default"], merge: true)
    }
}
