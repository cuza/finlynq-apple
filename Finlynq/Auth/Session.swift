import Foundation
import Observation

@Observable
final class Session {
    enum State: Equatable {
        case starting
        case locked              // saved credentials, waiting for Face ID / Touch ID
        case signedOut
        case needsCode           // password accepted, waiting for the 6-digit MFA code
        case signedIn
    }

    static let defaultServer = "https://finlynq.com"

    private(set) var state: State = .starting
    private(set) var info: SessionInfo?
    let api: APIClient

    /// Bumped after every change the app saves, so screens keyed on it reload.
    private(set) var revision = 0

    /// Accounts and categories, used by pickers and filters across screens.
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []

    var currency: String { info?.displayCurrency ?? "USD" }

    /// A fresh account that hasn't run first-run setup (Setup.dc.html) yet.
    private(set) var needsSetup = false

    /// Signed in to the shared public demo, which the app never writes settings to or deletes.
    var isDemo: Bool {
        !Fixtures.isEnabled && info?.username == Self.demo.username && api.baseURL.host() == URL(string: Self.defaultServer)?.host()
    }

    /// The public demo account on finlynq.com.
    static let demo = (username: "demo", password: "finlynq-demo")

    private var pending: Credentials?
    private var mfaToken: String?
    private var relogin: Task<Bool, Never>?

    init(api: APIClient = APIClient(baseURL: URL(string: defaultServer)!)) {
        self.api = api
        api.reauthenticate = { [weak self] in await self?.signInAgain() ?? false }
    }

    // MARK: Launch and unlock

    func start(requireBiometrics: Bool) async {
        if Fixtures.isEnabled {
            // Fixture mode: no Keychain, no biometrics, no network.
            if let info: SessionInfo = try? await api.get("/api/auth/session") { await finishSignIn(info) } else { state = .signedOut }
            return
        }
        guard let creds = Keychain.load() else { state = .signedOut; return }
        pending = creds
        api.baseURL = URL(string: creds.server) ?? api.baseURL
        if requireBiometrics && Biometrics.available {
            state = .locked
        } else {
            await resume()
        }
    }

    func unlock() async {
        if await Biometrics.unlock() { await resume() }
    }

    private func resume() async {
        // Reuse the saved cookie when the server still holds our encryption key.
        if let info: SessionInfo = try? await api.get("/api/auth/session"),
           info.authenticated, info.encryptionLocked != true {
            await finishSignIn(info)
        } else if !(await signInAgain()) {
            state = .signedOut
        }
    }

    // MARK: Sign in

    /// Returns an error message for the login form, or nil on success / MFA prompt.
    func signIn(server: String, username: String, password: String) async -> String? {
        guard let trimmed = use(server: server) else { return Self.badServer }
        let creds = Credentials(server: trimmed, username: username, password: password)
        do {
            return try await login(creds) ? nil : "Unexpected response from the server."
        } catch {
            return error.localizedDescription
        }
    }

    static let badServer = "Enter a server address starting with https://"

    /// Points the client at `server`. Returns the address without a trailing slash, or nil when it isn't a web address.
    func use(server: String) -> String? {
        let trimmed = server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", url.host() != nil else { return nil }
        api.baseURL = url
        return trimmed
    }

    func tryDemo() async -> String? {
        await signIn(server: Self.defaultServer, username: Self.demo.username, password: Self.demo.password)
    }

    /// Creates an account, then signs in to it. Returns an error message for the form, or nil on success.
    func register(server: String, username: String, email: String?, password: String) async -> String? {
        guard let trimmed = use(server: server) else { return Self.badServer }
        do {
            try await api.register(username: username, email: email, password: password)
        } catch {
            return error.localizedDescription
        }
        return await signIn(server: trimmed, username: username, password: password)
    }

    /// Back from the code step to the password form.
    func cancelCode() {
        mfaToken = nil
        pending = nil
        state = .signedOut
    }

    func submitCode(_ code: String) async -> String? {
        guard let mfaToken, let pending else { state = .signedOut; return nil }
        do {
            try await api.send("POST", "/api/auth/mfa/verify", body: ["mfaPendingToken": mfaToken, "code": code])
            self.mfaToken = nil
            Keychain.save(pending)
            await loadSession()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Posts the password. Returns true when signed in or waiting for an MFA code.
    private func login(_ creds: Credentials) async throws -> Bool {
        // The password only ever goes to the server it belongs to, whatever the client points at now.
        guard let server = URL(string: creds.server), server.host() != nil else {
            throw APIError.server(status: 0, message: Self.badServer)
        }
        api.baseURL = server
        api.clearCookies()
        let body = try JSONEncoder().encode(["identifier": creds.username, "password": creds.password])
        let data = try await api.send("POST", "/api/auth/login", body: body, retry: false)
        let response: LoginResponse = try api.decode(data)
        pending = creds
        // The MFA branch also answers 200, so check it before treating this as success.
        if response.mfaRequired == true, let token = response.mfaPendingToken {
            mfaToken = token
            state = .needsCode
            return true
        }
        guard response.success == true else { return false }
        Keychain.save(creds)
        await loadSession()
        return true
    }

    /// Signs in with the saved password after a 401/423. Concurrent callers share one attempt,
    /// because the server allows only 5 logins a minute.
    /// Only while signed in, locked or starting up: never from the sign-in form, where the saved password may
    /// belong to another server or account.
    func signInAgain() async -> Bool {
        guard [.signedIn, .locked, .starting].contains(state) else { return false }
        if let relogin { return await relogin.value }
        guard let creds = pending ?? Keychain.load() else { return false }
        let task = Task<Bool, Never> {
            // An MFA account can't sign in silently, so the login form shows instead.
            (try? await login(creds)) == true && state != .needsCode
        }
        relogin = task
        let succeeded = await task.value
        relogin = nil
        return succeeded
    }

    private func loadSession() async {
        guard let info: SessionInfo = try? await api.get("/api/auth/session"), info.authenticated else {
            state = .signedOut
            return
        }
        await finishSignIn(info)
    }

    private func finishSignIn(_ info: SessionInfo) async {
        self.info = info
        needsSetup = info.onboardingComplete == false
        state = .signedIn
        await refreshLookups()
    }

    func refreshLookups() async {
        async let fetchedAccounts: [Account]? = try? api.get("/api/accounts")
        async let fetchedCategories: [Category]? = try? api.get("/api/categories")
        if let fetchedAccounts = await fetchedAccounts { accounts = fetchedAccounts }
        if let fetchedCategories = await fetchedCategories {
            categories = fetchedCategories.sorted { ($0.group, $0.displayName) < ($1.group, $1.displayName) }
        }
    }

    /// Call after a successful save: reloads balances and categories, then tells keyed screens to reload.
    func didSave() async {
        await refreshLookups()
        revision += 1
    }

    /// Saves the display currency, then reloads the session (which carries it) and every keyed screen.
    func setDisplayCurrency(_ code: String) async throws {
        try await api.setDisplayCurrency(code)
        if let info: SessionInfo = try? await api.get("/api/auth/session"), info.authenticated { self.info = info }
        await didSave()
    }

    /// Marks first-run setup done on the server. A failure is ignored: setup shows again on the next sign-in.
    func finishSetup() async {
        _ = try? await api.completeOnboarding()
        needsSetup = false
        await didSave()
    }

    // MARK: Lock when idle

    /// The file the CSV export writes, removed on sign-out.
    nonisolated static let exportURL = FileManager.default.temporaryDirectory.appending(path: "Finlynq transactions.csv")

    private var leftAt: Date?

    /// True when the app was away for longer than `minutes`. Zero or less means never.
    static func idleTooLong(since leftAt: Date?, now: Date, minutes: Int) -> Bool {
        guard let leftAt, minutes > 0 else { return false }
        return now.timeIntervalSince(leftAt) > Double(minutes) * 60
    }

    /// The app went to the background or lost focus. Keeps the first time, so a background after inactive counts from inactive.
    func appLeft(now: Date) {
        if state == .signedIn, leftAt == nil { leftAt = now }
    }

    /// The app is back. Locks it when Face ID or Touch ID unlock is on and it was away too long.
    func appReturned(now: Date, requireBiometrics: Bool, lockAfterMinutes: Int) {
        defer { leftAt = nil }
        guard state == .signedIn, requireBiometrics, !Fixtures.isEnabled, Biometrics.available,
              Self.idleTooLong(since: leftAt, now: now, minutes: lockAfterMinutes) else { return }
        state = .locked
    }

    // MARK: Sign out

    func signOut() async {
        // The cookie (sent automatically) is what lets the server revoke the session.
        _ = try? await api.send("POST", "/api/auth/logout", retry: false)
        // Nothing of the account stays on the device: cookies for every host, cached responses, the exported CSV.
        for cookie in HTTPCookieStorage.shared.cookies ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
        URLCache.shared.removeAllCachedResponses()
        try? FileManager.default.removeItem(at: Self.exportURL)
        Keychain.delete()
        pending = nil
        info = nil
        needsSetup = false
        accounts = []
        categories = []
        // Waiting Apple Pay purchases and card mappings belong to this account.
        ApplePayCapture.store.clear()
        state = .signedOut
    }

    /// Deletes the account for good, then signs out and forgets the saved password.
    func deleteAccount(password: String, mfaCode: String?) async throws {
        guard !isDemo else { return }
        try await api.deleteAccount(password: password, mfaCode: mfaCode)
        await signOut()
    }

    var savedServer: String { pending?.server ?? Keychain.load()?.server ?? Self.defaultServer }
    var savedUsername: String { Keychain.isOff() ? "demo" : pending?.username ?? Keychain.load()?.username ?? "" }
}
