import SwiftUI

/// Changes a loan's name, rate, payment (or term) and extra payment. Only the fields the user changed are sent, so
/// edits made on the website to anything else stay as they are.
struct EditLoanSheet: View {
    let loan: Loan
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rate = ""
    /// The payment for a loan saved with one, else the term in months.
    @State private var payment = ""
    @State private var extra = ""
    @State private var saving = false
    @State private var error: String?

    /// Loans saved with a term let the server work out the payment, so the sheet edits the term instead.
    private var byTerm: Bool { loan.paymentAmount == nil && loan.termMonths != nil }
    private static let plain = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...4)).grouping(.never)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Annual rate (%)", text: $rate).numberPad()
                TextField(byTerm ? "Term (months)" : "Payment", text: $payment).numberPad()
                TextField("Extra each payment", text: $extra).numberPad()
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit loan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving) }
            }
            .onAppear {
                name = loan.displayName
                rate = loan.annualRate.formatted(Self.plain)
                payment = byTerm ? loan.termMonths.map(String.init) ?? "" : loan.paymentAmount.map { $0.formatted(Self.plain) } ?? ""
                extra = (loan.extraPayment ?? 0).formatted(Self.plain)
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func value(_ text: String) -> Double? {
        AddModel.number(text).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// The edited fields, or an error message for a field that isn't a number.
    private func changes() -> Result<LoanUpdate, LoanFormError> {
        var update = LoanUpdate(id: loan.id)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty && trimmedName != loan.displayName { update.name = trimmedName }
        guard let annualRate = value(rate), annualRate >= 0 else { return .failure(.init("Enter the annual rate as a number.")) }
        if annualRate != loan.annualRate { update.annualRate = annualRate }
        if byTerm {
            guard let months = Int(payment.trimmingCharacters(in: .whitespaces)), months > 0 else {
                return .failure(.init("Enter the term as a whole number of months."))
            }
            if months != loan.termMonths { update.termMonths = months }
        } else {
            guard let amount = value(payment), amount > 0 else { return .failure(.init("Enter the payment as a number.")) }
            if amount != loan.paymentAmount { update.paymentAmount = amount }
        }
        let extraAmount = value(extra) ?? 0
        if extraAmount != (loan.extraPayment ?? 0) { update.extraPayment = extraAmount }
        return .success(update)
    }

    private func save() async {
        let update: LoanUpdate
        switch changes() {
        case .failure(let failure):
            error = failure.message
            return
        case .success(let value): update = value
        }
        saving = true
        defer { saving = false }
        do {
            try await session.api.updateLoan(update)
            await session.didSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LoanFormError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Adds a loan with `POST /api/loans` (Debts and the Mac debts list). Linking an account makes its balance the
/// loan's balance; the loan takes that account's currency.
struct AddLoanSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "loan"
    @State private var accountId: Int?
    @State private var principal = ""
    @State private var rate = ""
    @State private var payment = ""
    @State private var start = Fixtures.today
    @State private var saving = false
    @State private var error: String?

    private var liabilities: [Account] { session.accounts.filter { $0.type == "L" && !$0.archived } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    Text("Loan").tag("loan")
                    Text("Mortgage").tag("mortgage")
                    Text("Student loan").tag("student")
                    Text("Lease").tag("lease")
                }
                Picker("Account", selection: $accountId) {
                    Text("None").tag(Int?.none)
                    ForEach(liabilities) { Text($0.displayName).tag(Int?.some($0.id)) }
                }
                TextField("Amount borrowed", text: $principal).numberPad()
                TextField("Annual rate (%)", text: $rate).numberPad()
                TextField("Monthly payment", text: $payment).numberPad()
                DatePicker("Start date", selection: $start, displayedComponents: .date)
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            .navigationTitle("New loan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }

    private func value(_ text: String) -> Double? {
        AddModel.number(text).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private func save() async {
        guard let amount = value(principal), amount > 0 else { error = "Enter the amount borrowed."; return }
        guard let annualRate = value(rate), annualRate >= 0 else { error = "Enter the annual rate as a number."; return }
        guard let monthly = value(payment), monthly > amount * annualRate / 1200 else {
            error = "Enter a monthly payment larger than the first month's interest."
            return
        }
        saving = true
        defer { saving = false }
        let currency = session.accounts.first { $0.id == accountId }?.currency ?? session.currency
        do {
            try await session.api.createLoan(LoanInput(
                name: name.trimmingCharacters(in: .whitespaces), type: type, accountId: accountId, currency: currency,
                principal: amount, annualRate: annualRate, termMonths: nil, startDate: APIDate.string(start), paymentAmount: monthly,
                paymentFrequency: "monthly", extraPayment: 0
            ))
            await session.didSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
