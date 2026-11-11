import Foundation
import LocalAuthentication
import Security

/// Saved sign-in details, so the app can sign in again when the server locks the session.
nonisolated struct Credentials: Codable, Equatable {
    var server: String
    var username: String
    var password: String
}

enum Keychain {
    private static let service = "dev.cuza.finlynq.credentials"

    /// The Security framework calls. Tests swap them to see whether the Keychain was touched.
    struct Calls {
        var add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
        var copy: (CFDictionary) -> AnyObject? = { query in
            var out: AnyObject?
            return SecItemCopyMatching(query, &out) == errSecSuccess ? out : nil
        }
        var delete: (CFDictionary) -> OSStatus = { SecItemDelete($0) }
    }

    static var calls = Calls()
    /// True in fixture mode, which never touches the Keychain: each ad-hoc signed build would make macOS ask
    /// for the login password to read the item an earlier build saved.
    static var isOff: () -> Bool = { Fixtures.isEnabled }

    // ponytail: plain generic-password item, unlocked by a Face ID/Touch ID prompt in the app.
    // Switch to a SecAccessControl(.userPresence) item once the app ships with a signing team.
    static func save(_ creds: Credentials) {
        guard !isOff(), let data = try? JSONEncoder().encode(creds) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        _ = calls.add(query as CFDictionary)
    }

    static func load() -> Credentials? {
        guard !isOff() else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        guard let data = calls.copy(query as CFDictionary) as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete() {
        guard !isOff() else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        _ = calls.delete(query as CFDictionary)
    }
}

enum Biometrics {
    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// What unlocks this device: "Face ID", "Touch ID", "Optic ID", or without biometry "Passcode" ("Password" on
    /// the Mac). Read once: the hardware doesn't change while the app runs.
    static let name: String = {
        let context = LAContext()
        // biometryType is set by this call, whatever it returns, so a device without enrolled fingers or faces
        // still reports its hardware.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return name(for: context.biometryType)
    }()

    static func name(for type: LABiometryType) -> String {
        switch type {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:
            #if os(macOS)
            return "Password"
            #else
            return "Passcode"
            #endif
        }
    }

    static let symbol = ["Face ID": "faceid", "Touch ID": "touchid", "Optic ID": "opticid"][name] ?? "lock"

    /// Face ID, Touch ID, or the device passcode as fallback.
    static func unlock() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Finlynq")) ?? false
    }
}
