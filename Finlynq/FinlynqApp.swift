import SwiftUI

@main
struct FinlynqApp: App {
    @State private var session = Session()
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @AppStorage("lockAfterMinutes") private var lockAfterMinutes = 5
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            screen
            .environment(session)
            .tint(Theme.accent)
            #if DEBUG
            .debugWindow()
            #endif
            .onChange(of: session.state, initial: true) {
                // Purchases captured offline, signed out or locked go out once the session is signed in.
                ApplePayCapture.live = session
                if session.state == .signedIn { Task { await ApplePayCapture.flush() } }
            }
            .task {
                // A unit-test host must not touch the Keychain: the access prompt blocks the main
                // thread and the test bundle never loads. UI tests set FINLYNQ_FIXTURES and still sign in.
                let env = ProcessInfo.processInfo.environment
                if env["XCTestConfigurationFilePath"] != nil && !Fixtures.isEnabled { return }
                await session.start(requireBiometrics: requireBiometrics)
            }
            // Lock again after the app has been away longer than "Lock automatically" allows. On the Mac the scene
            // stays active while its window is visible, so the app's own activation drives it there.
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                session.appLeft(now: Date())
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                appReturned()
            }
            #else
            .onChange(of: phase) { _, phase in
                if phase == .active { appReturned() } else { session.appLeft(now: Date()) }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        // The window's minimum is RootView's minimum frame, not its screens' ideal sizes.
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            MacSettingsView()
                .environment(session)
                .tint(Theme.accent)
        }
        #endif
    }

    private func appReturned() {
        session.appReturned(now: Date(), requireBiometrics: requireBiometrics, lockAfterMinutes: lockAfterMinutes)
    }

    @ViewBuilder
    private var screen: some View {
        #if DEBUG
        if let route = DebugRoute.current, route.isStandalone {
            Group { if route.name == "setup" { SetupView(model: .debugAccountsStep) } else { SignInView() } }
                .onAppear { DebugRoute.markReady() }
        } else {
            stateScreen
        }
        #else
        stateScreen
        #endif
    }

    @ViewBuilder
    private var stateScreen: some View {
        switch session.state {
        case .starting: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .locked: LockView()
        case .signedOut, .needsCode: SignInView()
        case .signedIn:
            // First run after a fresh registration. SetupView ends it through `session.finishSetup()`.
            RootView()
            #if os(iOS)
                .fullScreenCover(isPresented: .constant(session.needsSetup)) { SetupView() }
            #else
                .sheet(isPresented: .constant(session.needsSetup)) { SetupView().frame(minWidth: 560, minHeight: 640) }
            #endif
        }
    }
}
