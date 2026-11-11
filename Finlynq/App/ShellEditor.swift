import SwiftUI

/// An editor sheet that screens open through the shell, so it stays open with its draft when the width class
/// changes and the shell swaps tabs for the sidebar. A sheet presented by the screen itself would close with it.
enum ShellEditor: Identifiable {
    case newGoal, editGoal(Goal), addBill, addAccount, addLoan, importStatement
    case editAccount(Dashboard.Balance, Account?), editLoan(Loan)
    /// The Add sheet on Invest, with Buy or Sell filled in from a holding.
    case record(AddModel.InvestPrefill?)

    var id: String {
        switch self {
        case .newGoal: "newGoal"
        case .editGoal(let goal): "editGoal:\(goal.id)"
        case .addBill: "addBill"
        case .addAccount: "addAccount"
        case .addLoan: "addLoan"
        case .editAccount(let balance, _): "editAccount:\(balance.id)"
        case .importStatement: "importStatement"
        case .editLoan(let loan): "editLoan:\(loan.id)"
        case .record(let prefill):
            "record:" + (prefill.map { "\($0.operation.rawValue)|\($0.symbol ?? "")|\($0.accountId ?? 0)" } ?? "")
        }
    }
}

extension ShellEditor {
    /// The root host and the iPhone Settings sheet's host each present editors. On a width change an open editor
    /// moves to the host that stays on screen: to the root on regular width (the Settings sheet becomes a sidebar
    /// page), and into the Settings sheet on compact width when that sheet will show. So the two hosts never present
    /// at once and no stale editor comes back later.
    static func handOff(root: inout ShellEditor?, settings: inout ShellEditor?, toCompact: Bool, showsSettings: Bool) {
        if !toCompact, let open = settings {
            root = open
            settings = nil
        } else if toCompact, showsSettings, let open = root {
            settings = open
            root = nil
        }
    }
}

extension EnvironmentValues {
    /// Opens an editor sheet from the shell.
    @Entry var presentEditor = ShellAction<ShellEditor>(host: "none") { _ in }
    /// Opens Settings: the sheet over Home on iPhone.
    @Entry var showSettings = ShellAction<Void>(host: "none") {}
}

/// A shell callback in the environment. SwiftUI can't compare closures, so a bare closure counts as changed on
/// every environment update and redraws every screen that reads it. With the account pushed over Accounts on the Mac,
/// those redraws updated the toolbar, which updated the environment again, and the app spun at 100% CPU.
/// Actions compare by the host that set them, and a new action from the same host is ignored. So the rule: an
/// action's closure may reach state only through State, Binding or a reference type, never through a value it
/// captured, and an action that does something different needs a new host id. The root and the iPhone Settings sheet
/// each present their own editors, so each `ShellEditorHost` has its own id.
struct ShellAction<Input>: Equatable {
    let host: AnyHashable
    let run: @MainActor (Input) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.host == rhs.host }

    @MainActor func callAsFunction(_ input: Input) { run(input) }
}

extension ShellAction where Input == Void {
    @MainActor func callAsFunction() { run(()) }
}

/// Presents the shell's editor sheets. Deleting a goal from its own page closes the page once the sheet is gone.
struct ShellEditorHost: ViewModifier {
    @Binding var editor: ShellEditor?
    /// Pops the page the goal editor was opened from.
    let popPage: () -> Void
    @State private var deletedGoal = false
    /// This host, so its action differs from the other host's.
    @State private var host = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.presentEditor, ShellAction(host: host) { editor = $0 })
            .sheet(item: $editor, onDismiss: {
                if deletedGoal { popPage() }
                deletedGoal = false
            }, content: { editor in
                switch editor {
                case .newGoal: GoalEditor()
                case .editGoal(let goal): GoalEditor(goal: goal) { deletedGoal = true }
                case .addBill: AddBillSheet()
                case .addAccount: AddAccountSheet()
                case .addLoan: AddLoanSheet()
                case .editAccount(let balance, let account): EditAccountSheet(balance: balance, account: account)
                case .editLoan(let loan): EditLoanSheet(loan: loan)
                case .importStatement: ImportSheet()
                case .record(let prefill): AddSheet(kind: .invest, invest: prefill)
                }
            })
    }
}
