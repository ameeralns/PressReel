import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

@MainActor
class AuthenticationService: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String?
    
    init() {
        user = Auth.auth().currentUser
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }
    
    // MARK: - Email Authentication
    func signUpWithEmail(email: String, password: String, firstName: String? = nil, lastName: String? = nil) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Update user profile with name if provided
            if let firstName = firstName, let lastName = lastName {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = "\(firstName) \(lastName)"
                try await changeRequest.commitChanges()
            }
            
            self.user = result.user
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func signInWithEmail(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.user = result.user
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Google Authentication
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw AuthError.noRootViewController
        }
        
        do {
            let userAuthentication = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            let user = userAuthentication.user
            guard let idToken = user.idToken?.tokenString else { throw AuthError.invalidCredential }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            let result = try await Auth.auth().signIn(with: credential)
            self.user = result.user
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Sign Out
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            self.user = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}

// MARK: - Error Handling
enum AuthError: Error {
    case noRootViewController
    case invalidCredential
} 