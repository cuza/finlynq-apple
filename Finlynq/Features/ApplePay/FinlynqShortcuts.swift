import AppIntents

/// Lists the Apple Pay action in Shortcuts as soon as the app is installed, with no setup in the app.
struct FinlynqShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPurchaseIntent(),
            phrases: ["Add an Apple Pay purchase to \(.applicationName)"],
            shortTitle: "Add Apple Pay purchase",
            systemImageName: "creditcard"
        )
    }
}
