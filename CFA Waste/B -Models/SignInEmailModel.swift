import Foundation

struct SignInEmailModel {
    let pin: String

    init(pin: String) {
        self.pin = pin
    }

    // Validation Logic
    func isValid() -> Bool {
        return !pin.isEmpty
    }
    
    // Error Handling for Validation
    func validationError() -> String? {
        if pin.isEmpty {
            return "PIN cannot be empty."
        }
        // Optional: enforce 5-digit numeric PIN
        if pin.count != 5 || pin.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return "PIN must be exactly 5 digits."
        }
        return nil
    }
}
