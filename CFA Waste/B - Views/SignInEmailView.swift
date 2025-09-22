import SwiftUI
import FirebaseAuth
// If HomeView is in another module, import it here. Otherwise, this is fine.

struct SignInEmailView: View {
    @StateObject private var viewModel = SignInEmailViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                // Fullscreen Background Image
                Image("SignInBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // Frosted Glass Container
                VStack {
                    Spacer()

                    // Sign In Title
                    Text("Enter PIN")
                        .font(.system(size: 96, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                        .padding(.bottom, 20)

                    VStack(spacing: 20) {
                        // PIN Field
                        SecureField("Enter 5-digit PIN", text: $viewModel.pin)
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

                        // Loading Indicator or Sign-In Button
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Button("Sign In", action: {
                                viewModel.errorMessage = ""
                                viewModel.signIn()
                            })
                            .disabled(viewModel.pin.isEmpty)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 240, height: 50)
                            .background(viewModel.pin.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                        }

                        NavigationLink("Register PIN", destination: RegistrationView())
                            .foregroundColor(.blue)
                            .padding(.top, 10)
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
        .fullScreenCover(isPresented: $viewModel.isSignedIn) {
            HomeView().environmentObject(authViewModel)
        }
    }
}
#Preview {
    NavigationStack {
        SignInEmailView()
    }
    
}
