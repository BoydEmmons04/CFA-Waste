//
//  AuthenticationView.swift
//  CFA Waste
//
//  Created by Boyd Emmons on 9/22/24.
//

import SwiftUI

struct AuthenticationView: View {
    var body: some View {
        VStack {
            NavigationLink {
                SignInEmailView()
                    
            } label: {
                Text("Sign In with PIN")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .bold()
                    .frame(height: 55)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(20)
            }
            .padding()
            
            NavigationLink {
                RegistrationView()
            } label: {
                Text("Register PIN")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .bold()
                    .frame(height: 55)
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(20)
            }
            .padding()
        }
        .navigationTitle("PIN Authentication")
    }
}

#Preview {
    NavigationStack {
        AuthenticationView()
    }
    
}
