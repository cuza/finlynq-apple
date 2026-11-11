import SwiftUI

/// Sign in (SignIn.dc.html), the 6-digit MFA code step, and creating an account. "Try the demo" signs in to the
/// shared demo on finlynq.com. A self-hosted server goes in an extra field.
struct SignInView: View {
    private enum Mode { case signIn, register }

    @Environment(Session.self) private var session
    @State private var mode = Mode.signIn
    @State private var server = Session.defaultServer
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var noRecovery = false
    @State private var code = ""
    @State private var selfHosted = false
    @State private var busy = false
    @State private var error: String?

    private var needsCode: Bool { session.state == .needsCode }

    private var canSubmit: Bool {
        if busy { return false }
        if needsCode { return code.count == 6 }
        if mode == .register { return username.count >= 3 && !password.isEmpty && (!email.isEmpty || noRecovery) }
        return !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        // The form sits in the middle of the screen, 420pt wide at most (SignIn.dc.html, iPadPSignIn.dc.html).
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    logo.padding(.bottom, 14)
                    fields
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.negative).padding(.horizontal, 4)
                            .accessibilityIdentifier("signInError")
                    }
                    primaryButton
                    if needsCode {
                        Button("Back to sign in") { session.cancelCode(); code = "" }
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent).buttonStyle(.plain)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else {
                        serverRow
                        if mode == .signIn { demo }
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24).padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.page)
        .safeAreaInset(edge: .bottom) { if !needsCode { switchMode } }
        .onSubmit { Task { await submit() } }
        .onAppear {
            server = session.savedServer
            username = session.savedUsername
            selfHosted = server != Session.defaultServer
        }
    }

    // MARK: Parts

    private var logo: some View {
        VStack(spacing: 12) {
            FinlynqMark()
                .stroke(.white, style: StrokeStyle(lineWidth: 2.2 * 40 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 40)
                .frame(width: 76, height: 76)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 10)
                .accessibilityHidden(true)
            Text("Finlynq").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
            Text(tagline).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
    }

    private var tagline: String {
        if needsCode { return "Enter the 6-digit code from your authenticator app." }
        if mode == .register { return "Create an account. Your data is encrypted with your password." }
        return "Open-source money tracking for spending, budgets and investments."
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 0) {
            if needsCode {
                field("Code") {
                    TextField("123456", text: $code)
                        .textContentType(.oneTimeCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            } else {
                field(mode == .register ? "Username" : "Email or username") {
                    TextField("", text: $username).textContentType(.username).plainEntry()
                }
                if mode == .register {
                    Divider()
                    field("Email (for password resets)") {
                        TextField("Optional", text: $email).textContentType(.emailAddress).plainEntry()
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            #endif
                    }
                }
                Divider()
                field("Password") {
                    SecureField("", text: $password).textContentType(mode == .register ? .newPassword : .password)
                }
                if selfHosted {
                    Divider()
                    field("Server") {
                        TextField("https://", text: $server).textContentType(.URL).plainEntry()
                            #if os(iOS)
                            .keyboardType(.URL)
                            #endif
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .settingsCard()
        if mode == .register && email.isEmpty && !needsCode {
            Toggle("I understand that without an email I can never reset my password.", isOn: $noRecovery)
                .font(.footnote).foregroundStyle(Theme.secondary).tint(Theme.accent).padding(.horizontal, 4)
        }
    }

    private func field(_ label: String, @ViewBuilder input: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.secondary)
            input().font(.body).foregroundStyle(Theme.text).textFieldStyle(.plain).accessibilityLabel(label)
        }
        .padding(.vertical, 10)
    }

    private var primaryButton: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(needsCode ? "Verify" : mode == .register ? "Create account" : "Sign in")
            }
            .font(.body.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Theme.accent.opacity(canSubmit || busy ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityIdentifier("signInButton")
    }

    private var serverRow: some View {
        HStack {
            Label(URL(string: server)?.host() ?? server, systemImage: "server.rack")
                .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
            Spacer()
            Button(selfHosted ? "Use finlynq.com" : "Use a self-hosted server") {
                selfHosted.toggle()
                if !selfHosted { server = Session.defaultServer }
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent).buttonStyle(.plain)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 4)
    }

    private var demo: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Rectangle().fill(Theme.fill).frame(height: 1)
                Text("or").font(.footnote).foregroundStyle(Theme.secondary)
                Rectangle().fill(Theme.fill).frame(height: 1)
            }
            .accessibilityHidden(true)
            Button { Task { await tryDemo() } } label: {
                Text("Try the demo")
                    .font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.badge))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            Text("Look around a shared account with sample data.").font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity).padding(.top, -4)
        }
    }

    private var switchMode: some View {
        HStack(spacing: 4) {
            Text(mode == .signIn ? "New to Finlynq?" : "Already have an account?").foregroundStyle(Theme.secondary)
            Button(mode == .signIn ? "Create account" : "Sign in") {
                mode = mode == .signIn ? .register : .signIn
                error = nil
            }
            .fontWeight(.semibold).foregroundStyle(Theme.accent).buttonStyle(.plain)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    // MARK: Actions

    private func submit() async {
        guard canSubmit else { return }
        busy = true
        defer { busy = false }
        let server = selfHosted ? server : Session.defaultServer
        if needsCode {
            error = await session.submitCode(code)
        } else if mode == .register {
            let email = email.trimmingCharacters(in: .whitespaces)
            error = await session.register(server: server, username: username.trimmingCharacters(in: .whitespaces),
                                           email: email.isEmpty ? nil : email, password: password)
        } else {
            error = await session.signIn(server: server, username: username, password: password)
        }
    }

    private func tryDemo() async {
        busy = true
        defer { busy = false }
        selfHosted = false
        server = Session.defaultServer
        error = await session.tryDemo()
    }
}

/// The Finlynq mark from SignIn.dc.html: three bars on a baseline under a rising line, on a 24-point grid.
nonisolated struct FinlynqMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        for (x, top) in [(4.0, 11.0), (10, 5), (16, 14)] {
            path.move(to: point(x, 20))
            path.addLine(to: point(x, top))
        }
        path.move(to: point(2, 20))
        path.addLine(to: point(22, 20))
        path.move(to: point(3, 9))
        path.addLines([point(3, 9), point(9, 4), point(15, 10), point(21, 5)])
        return path
    }
}

private extension View {
    /// No autocapitalization or autocorrection, for usernames, emails and addresses.
    func plainEntry() -> some View {
        autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }
}

/// Shown at launch when the saved password needs Face ID or Touch ID first.
struct LockView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var phase
    /// Each lock shows a new LockView, so this asks once per lock. The Face ID sheet makes the app inactive, and
    /// asking on every return to active would reopen it after a cancel. After the first ask only Unlock asks.
    @State private var prompted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Finlynq is locked").font(.title2.bold())
            Button("Unlock with \(Biometrics.name)", systemImage: Biometrics.symbol) { Task { await session.unlock() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Face ID fails with "UI activation timed out" if asked before the window is active.
        .task(id: phase) {
            guard phase == .active, !prompted else { return }
            prompted = true
            await session.unlock()
        }
    }
}
