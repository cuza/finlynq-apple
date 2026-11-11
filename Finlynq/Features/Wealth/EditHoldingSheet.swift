import SwiftUI

/// Edits one holding row with `PUT /api/portfolio` (Holding.dc.html, MacInvestments.dc.html). A holding held in
/// several accounts has one row per account, so the account is picked first. Only the changed fields are sent.
struct EditHoldingSheet: View {
    let positions: [PortfolioOverview.Position]
    /// Gets the new symbol after a save that changed it, so the screen showing the holding can follow it.
    var onRename: (String) -> Void = { _ in }
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var positionId: Int
    @State private var rows: [PortfolioHolding] = []
    @State private var original = WealthModel.HoldingFields(name: "", symbol: "", currency: "", isCrypto: false, note: "")
    @State private var fields = WealthModel.HoldingFields(name: "", symbol: "", currency: "", isCrypto: false, note: "")
    @State private var saving = false
    @State private var error: String?

    init(positions: [PortfolioOverview.Position], onRename: @escaping (String) -> Void = { _ in }) {
        self.positions = positions
        self.onRename = onRename
        let id = positions.first?.id ?? 0
        _positionId = State(initialValue: id)
        let start = Self.fields(id, positions: positions, rows: [])
        _original = State(initialValue: start)
        _fields = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            Form {
                if positions.count > 1 {
                    Picker("Account", selection: $positionId) {
                        ForEach(positions) { Text($0.accountName ?? "Account \($0.accountId ?? 0)").tag($0.id) }
                    }
                }
                Section {
                    TextField("Name", text: $fields.name)
                    TextField("Symbol or currency code", text: $fields.symbol)
                        .autocorrectionDisabled()
                    TextField("Currency", text: $fields.currency)
                        .autocorrectionDisabled()
                    Toggle("Crypto", isOn: $fields.isCrypto)
                    TextField("Note", text: $fields.note, axis: .vertical)
                } footer: {
                    Text("Changes this holding in the selected account. Its transactions stay as they are.")
                }
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit holding")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(fields.name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .task { await loadRows() }
            .onChange(of: positionId) { reset() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340)
        #endif
    }

    /// The saved row has the note and crypto flag, which the portfolio overview leaves out. The sheet starts from
    /// the overview's position; when the row arrives it fills only the fields the user hasn't changed. Without it
    /// (in fixture mode, or when the request fails) the position's values stay.
    private func loadRows() async {
        do {
            rows = try await session.api.portfolioHoldings()
        } catch is CancellationError {
            return
        } catch {
            WealthView.log.error("holding rows failed: \(String(describing: error), privacy: .public)")
            return
        }
        let saved = Self.fields(positionId, positions: positions, rows: rows)
        fields = WealthModel.prefill(fields, shown: original, saved: saved)
        original = saved
    }

    /// Another account picked: start over from its row.
    private func reset() {
        original = Self.fields(positionId, positions: positions, rows: rows)
        fields = original
    }

    private static func fields(
        _ id: Int, positions: [PortfolioOverview.Position], rows: [PortfolioHolding]
    ) -> WealthModel.HoldingFields {
        let position = positions.first { $0.id == id }
        let row = rows.first { $0.id == id }
        return WealthModel.HoldingFields(
            name: row?.name ?? position?.name ?? "", symbol: row?.symbol ?? position?.symbol ?? "",
            currency: row?.currency ?? position?.currency ?? "",
            isCrypto: row.map { $0.isCrypto == 1 } ?? (position?.assetType == "crypto"), note: row?.note ?? ""
        )
    }

    private func save() async {
        var edited = fields
        edited.name = edited.name.trimmingCharacters(in: .whitespaces)
        edited.symbol = edited.symbol.trimmingCharacters(in: .whitespaces)
        edited.currency = edited.currency.trimmingCharacters(in: .whitespaces).uppercased()
        guard let update = WealthModel.holdingUpdate(id: positionId, original: original, edited: edited) else {
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await session.api.updateHolding(update)
            await session.didSave()
            if let symbol = update.symbol { onRename(symbol) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
