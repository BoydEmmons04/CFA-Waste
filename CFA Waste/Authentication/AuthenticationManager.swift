//
//  AuthenticationManager.swift
//  CFA Waste
//
//  Created by Boyd Emmons on 9/22/24.
//

import Foundation
import FirebaseAuth

class AuthenticationManager {
    static let shared = AuthenticationManager()
    
    private init() {}
    
    // MARK: - Create User (Registration)
    func createUser(pin: String) async throws -> User {
        let fakeEmail = "\(pin)@myapp.local"
        // Pad PIN to meet Firebase minimum password length
        let fakePassword = pin + "X"
        let authResult = try await Auth.auth().createUser(withEmail: fakeEmail, password: fakePassword)
        return authResult.user
    }

    // MARK: - Sign In User
    func signIn(pin: String) async throws -> User {
        let fakeEmail = "\(pin)@myapp.local"
        // Use same padding logic as registration
        let fakePassword = pin + "X"
        let authResult = try await Auth.auth().signIn(withEmail: fakeEmail, password: fakePassword)
        return authResult.user
    }
    
    // MARK: - Get Current User
    func getCurrentUser() -> User? {
        return Auth.auth().currentUser
    }

    // MARK: - Sign Out
    func signOut() throws {
        try Auth.auth().signOut()
    }
    
    // MARK: - Delete User
    func deleteUser() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "NoUserError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in."])
        }
        try await user.delete()
    }
}
