import Foundation
import FirebaseAuth

@MainActor
final class RegistrationViewModel: ObservableObject {
    @Published var pin: String = ""
    @Published var confirmPin: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""

    var isInputValid: Bool {
        !pin.isEmpty && pin == confirmPin
    }

    func register() {
        guard pin == confirmPin else {
            errorMessage = "PINs do not match."
            return
        }
        
        Task {
            // Start loading
            await MainActor.run {
                isLoading = true
                errorMessage = ""
            }
            
            do {
                let user = try await AuthenticationManager.shared.createUser(pin: pin)
                print("User registered successfully with PIN: \(pin)")
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
}
