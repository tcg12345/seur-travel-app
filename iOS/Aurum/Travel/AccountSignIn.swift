import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct AccountAuthOptions: Decodable { var apple: Bool; var google: Bool; var email: Bool; var minimumPasswordLength: Int }
struct PendingEmailAccount: Decodable { var pending: Bool; var email: String }
enum AccountSignIn {
    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw JourneyError.message("Could not start secure sign-in. Please try again.") }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func nonceHash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func code(from url: URL) throws -> String {
        guard url.scheme == "seur", url.host == "auth", url.path == "/callback", url.user == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !components.queryItems.orEmpty.contains(where: { $0.name == "error" }),
              let value = components.queryItems?.first(where: { $0.name == "code" })?.value, !value.isEmpty else { throw JourneyError.message("Sign-in did not finish. Please try again.") }
        return value
    }
    static func validEmail(_ value: String) -> Bool { value.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil && value.count <= 254 }
}
private extension Optional where Wrapped == [URLQueryItem] { var orEmpty: [URLQueryItem] { self ?? [] } }

@MainActor final class GoogleSignInSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func signIn(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "seur") { [weak self] callback, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error { continuation.resume(throwing: error) }
                    else if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: JourneyError.message("Google sign-in did not finish.")) }
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { self.session = nil; continuation.resume(throwing: JourneyError.message("Could not open Google sign-in.")) }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow()
    }
}

struct AccountProfileEditor: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var handle = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Your profile") { TextField("Display name", text: $name).textContentType(.name); TextField("Username", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Section { Text("Friends find you by your username. Changing it keeps your trips, friends and conversations.").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { saving = true; defer { saving = false }; do { try await api.updateProfile(name: name, handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear { name = api.account?.name ?? ""; handle = api.account?.handle ?? "" }.interactiveDismissDisabled(saving)
        }
    }
}
