import Foundation
import FirebaseAuth
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
