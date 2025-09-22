import SwiftUI

struct RegistrationView: View {
    @StateObject private var viewModel = RegistrationViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Fullscreen Background Image
                Image("RegisterBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // Frosted Glass Container
                VStack {
                    Spacer()

                    // Registration Title
                    Text("Register PIN")
                        .font(.system(size: 96, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                        .padding(.bottom, 20)

                    VStack(spacing: 20) {
                        // PIN Fields
                        SecureField("Enter 5-digit PIN", text: $viewModel.pin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .padding()
                            .frame(width: 336, height: 50)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .font(.system(size: 18, weight: .bold))
                            .cornerRadius(10)

                        SecureField("Confirm PIN", text: $viewModel.confirmPin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .padding()
                            .frame(width: 336, height: 50)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .font(.system(size: 18, weight: .bold))
                            .cornerRadius(10)

                        // Error Message
                        if !viewModel.errorMessage.isEmpty {
                            Text(viewModel.errorMessage)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Loading Indicator or Register Button
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Button("Register PIN", action: {
                                // Clear any previous error
                                viewModel.errorMessage = ""
                                // Trigger registration in ViewModel
                                viewModel.register()
                            })
                            .disabled(!viewModel.isInputValid)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 240, height: 50)
                            .background(viewModel.isInputValid ? Color.blue : Color.gray)
                            .cornerRadius(10)
                        }

                        // Hyperlink-style Button to go back to SignInView
                        NavigationLink(destination: SignInEmailView()) {
                            Text("Already have a PIN? Sign In")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .underline()
                        }
                        
                        .padding(.bottom, 10)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .frame(width: 336)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}
#Preview {
    RegistrationView()
}
