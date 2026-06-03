import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class SignInEmailViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var pin: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var isSignedIn: Bool = false  // Used for navigation or app state changes

    // MARK: - Sign-In Method
    func signIn() {
        // Create a SignInEmailModel to validate the user input
        let signInModel = SignInEmailModel(pin: pin)
        
        // Validate input using the model
        if let error = signInModel.validationError() {
            errorMessage = error
            return
        }
        
        // Start loading
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let returnedUserData = try await AuthenticationManager.shared.signIn(pin: signInModel.pin)
                print("Success: \(returnedUserData)")

                // One-time, idempotent backfill of account docs
                if let uid = Auth.auth().currentUser?.uid {
                    await backfillAccountDocsIfNeeded(uid: uid, pin: signInModel.pin)
                }

                await MainActor.run {
                    isSignedIn = true
                    errorMessage = ""
                }
            } catch {
                let message = handleError(error)
                print("Error during sign-in: \(error)")
                await MainActor.run {
                    errorMessage = message
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }

    /// One-time backfill: ensure users/{uid}/account/ has Name, Number, TopBannerSetting.
    /// This is idempotent and safe to call on every sign-in.
    private func backfillAccountDocsIfNeeded(uid: String, pin: String) async {
        let db = Firestore.firestore()
        let account = db.collection("users").document(uid).collection("account")

        do {
            let snapshot = try await account.getDocuments()
            let existing = Set(snapshot.documents.map { $0.documentID })

            if !existing.contains("Name") {
                try await account.document("Name").setData(["value": ""], merge: true)
            }
            if !existing.contains("Number") {
                let pinInt = Int(pin) ?? 0
                try await account.document("Number").setData(["value": pinInt], merge: true)
            }
            if !existing.contains("TopBannerSetting") {
                try await account.document("TopBannerSetting").setData(["value": "default"], merge: true)
            }
        } catch {
            // Non-fatal: log and continue sign-in flow
            print("Backfill error: \(error)")
        }
    }

    // MARK: - Error Handling
    private func handleError(_ error: Error) -> String {
        if let authError = error as NSError?, let errorCode = AuthErrorCode(rawValue: authError.code) {
            switch errorCode {
            case .userNotFound, .wrongPassword:
                return "PIN doesn't exist."
            default:
                return "An unknown error occurred. Please try again."
            }
        }
        return "An unknown error occurred. Please try again."
    }
}
