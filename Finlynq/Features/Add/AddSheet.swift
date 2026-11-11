import SwiftUI

/// The Add sheet (Add.dc.html, Invest.dc.html, iPadAdd.dc.html). iPhone shows its own number pad and puts payee and
/// note behind a chip, iPad and Mac show an amount field and inline payee and note rows.
struct AddSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddModel
    @State private var quick: [Category] = []
    @State private var error: String?

    init(kind: AddModel.Kind = .expense, invest: AddModel.InvestPrefill? = nil) {
        _model = State(initialValue: AddModel(kind: kind, invest: invest))
    }

    /// The sheet's width, nil until measured. An iPad form sheet reports a compact size class too, so the keypad
    /// goes by width, and until then by the window's size class.
    @State private var width: CGFloat?
    @Environment(\.shellSizeClass) private var sizeClass

    /// The number pad, in a phone-width sheet (iPhone, iPhone Duo closed). Wider sheets and the Mac get an amount field.
    private var usesPad: Bool {
        #if os(iOS)
        Self.usesPad(width: width, sizeClass: sizeClass)
        #else
        false
        #endif
    }

    /// The text size is held at the default, so larger text never swaps an iPad's amount field for the pad.
    static func usesPad(width: CGFloat?, sizeClass: UserInterfaceSizeClass?) -> Bool {
        LayoutWidth(measured: width, typeSize: .large, sizeClass: sizeClass) == .compact
    }

    private var categories: [Category] {
        session.categories.filter { $0.type == model.kind.categoryType }
    }

    private var accounts: [Account] { session.accounts.filter { !$0.archived } }
    private var account: Account? { session.accounts.first { $0.id == model.accountId } }

    var body: some View {
        NavigationStack {
            // The bar sits below the scroll view, not over it, so the last row can always scroll into view.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: usesPad ? 12 : 14) {
                        Picker("Type", selection: $model.kind) {
                            ForEach(AddModel.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("addKind")
                        if model.kind == .invest {
                            InvestForm(model: model, usesPad: usesPad)
                        } else {
                            amountField
                            if model.kind == .transfer { transferAccounts } else { categoryGrid }
                            chips
                            if !usesPad { PayeeNoteRows(model: model) }
                        }
                    }
                    .padding(.horizontal, usesPad ? 20 : 24)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }
            .background(Theme.card)
            .navigationTitle(model.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            }
            .horizontalBar()
        }
        .presentationBackground(Theme.card)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 700)
        #endif
        .task { await prepare() }
        // The debug route can open the sheet before the accounts arrive.
        .onChange(of: session.accounts) { _, _ in applyDefaultAccount() }
        .onChange(of: model.kind) { _, _ in
            model.categoryId = nil
            error = nil
            model.accountId = nil
            model.toAccountId = nil
            applyDefaultAccount()
            Task { await loadQuick() }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var amountField: some View {
        if usesPad {
            HStack(alignment: .top, spacing: 2) {
                Text(currencySymbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .padding(.top, 8)
                Text(model.amountText.isEmpty ? "0" : model.amountText)
                    .font(.system(size: 58, weight: .bold)).tracking(-1.7).monospacedDigit()
                    .foregroundStyle(model.amountText.isEmpty ? Theme.secondary : Theme.text)
                    .accessibilityIdentifier("addAmount")
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.top, 6).padding(.bottom, 2)
        } else {
            HStack(spacing: 4) {
                Text(currencySymbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.secondary)
                TextField("0.00", text: $model.amountText)
                    .font(.system(size: 56, weight: .bold)).tracking(-1.7).monospacedDigit()
                    .textFieldStyle(.plain)
                    .fixedSize()
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Amount")
                    .accessibilityIdentifier("addAmount")
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Theme.page, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2))
        }
    }

    private var currencySymbol: String {
        let code = account?.currency ?? session.currency
        return (0.0).formatted(.currency(code: code).presentation(.narrow)).filter { !$0.isNumber && !$0.isPunctuation }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !usesPad {
                Text("Category").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(displayedCategories) { category in
                    let icon = Icons.category(category)
                    let selected = model.categoryId == category.id
                    Button { model.categoryId = category.id } label: {
                        CategoryTile(symbol: icon.0, tint: selected ? Theme.accent : icon.1, title: category.displayName,
                                     selected: selected, height: usesPad ? 66 : 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Menu {
                    Picker("Category", selection: $model.categoryId) {
                        ForEach(categories) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                } label: {
                    CategoryTile(symbol: "magnifyingglass", tint: Theme.inactive, title: "All", selected: false,
                                 dashed: true, height: usesPad ? 66 : 64)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
        }
    }

    /// The quick categories, with a category picked from "All" shown in place of the last one.
    private var displayedCategories: [Category] {
        var list = quick.isEmpty ? Array(categories.prefix(7)) : quick
        if let id = model.categoryId, !list.contains(where: { $0.id == id }), let picked = categories.first(where: { $0.id == id }) {
            list = Array(list.prefix(6)) + [picked]
        }
        return list
    }

    private var transferAccounts: some View {
        AddGroup {
            AddAccountRow(title: "From", selection: $model.accountId, options: accounts)
            Divider()
            AddAccountRow(title: "To", selection: $model.toAccountId, options: accounts)
        }
    }

    /// Account (not for transfers, which pick both above), date and, on iPhone, the payee and note chip.
    private var chips: some View {
        HStack(spacing: 8) {
            if model.kind != .transfer {
                Menu {
                    Picker("Account", selection: $model.accountId) {
                        ForEach(accounts) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                } label: {
                    AddChip(symbol: "creditcard", text: account?.displayName ?? "Account", large: !usesPad)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .accessibilityLabel("Account: \(account?.displayName ?? "none")")
                .accessibilityIdentifier("addAccount")
            }
            AddDateButton(date: $model.date) {
                AddChip(symbol: usesPad ? nil : "calendar", text: dayLabel(model.date, long: !usesPad), large: !usesPad)
            }
            .accessibilityIdentifier("addDate")
            if usesPad { PayeeNoteChip(model: model) }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if usesPad && model.kind != .invest { AmountPad(onPress: model.press) }
            // Next to the button, so a failed save is always on screen.
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.negative).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).accessibilityIdentifier("addError")
            }
            Button { Task { await save() } } label: {
                Text(buttonTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(model.canSave && !model.isSaving ? 1 : 0.45)
            .disabled(!model.canSave || model.isSaving)
            .accessibilityIdentifier("addSave")
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, usesPad ? 20 : 24)
        .padding(.top, 8)
        .padding(.bottom, usesPad ? 4 : 24)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
    }

    private var buttonTitle: String {
        if model.kind == .invest { return "Record \(model.operation.rawValue)" }
        let name = categories.first { $0.id == model.categoryId }?.displayName
        return model.buttonTitle(currency: account?.currency ?? session.currency, categoryName: name)
    }

    // MARK: Actions

    private func prepare() async {
        applyDefaultAccount()
        await loadQuick()
    }

    private func applyDefaultAccount() {
        // The Invest form picks its own accounts.
        guard model.accountId == nil, model.kind != .invest else { return }
        model.accountId = accounts.first { !$0.isInvestment }?.id ?? accounts.first?.id
    }

    private func loadQuick() async {
        guard model.kind.categoryType != nil else { return }
        let since = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        let page = try? await session.api.transactions(.init(startDate: APIDate.string(since), limit: 300))
        quick = AddModel.quickCategories(recent: page?.data ?? [], all: session.categories, kind: model.kind)
    }

    /// Closes the sheet only after the server accepted the entry, then reloads the screens behind it.
    private func save() async {
        error = nil
        do {
            guard try await model.save(api: session.api) else { return }
            dismiss()
            await session.didSave()
        } catch {
            self.error = error.localizedDescription
            AccessibilityNotification.Announcement(error.localizedDescription).post()
        }
    }
}

/// "Today", "Yesterday" or "Nov 7". The long form adds the date to today and yesterday: "Today, Nov 9".
func dayLabel(_ date: Date, long: Bool) -> String {
    let day = date.formatted(.dateTime.month(.abbreviated).day())
    let calendar = Calendar.current
    let relative = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday" : nil
    guard let relative else { return day }
    return long ? "\(relative), \(day)" : relative
}

// MARK: - Add sheet parts

/// A category button in the 4 by 2 grid.
private struct CategoryTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let selected: Bool
    var dashed = false
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(tint).frame(height: 20)
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
                .foregroundStyle(selected ? Theme.accent : dashed ? Theme.inactive : Theme.text)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(selected ? Theme.accentTint : Theme.card, in: shape)
        .overlay {
            if selected {
                shape.strokeBorder(Theme.accent, lineWidth: 2)
            } else if dashed {
                shape.strokeBorder(Theme.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                shape.strokeBorder(Theme.secondary.opacity(0.18))
            }
        }
        .contentShape(shape)
    }
}

/// A grey capsule: account, date and "+ Payee, note".
struct AddChip: View {
    var symbol: String?
    let text: String
    var secondary = false
    /// iPad and Mac use 14pt text.
    var large = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
            Text(text).font(.system(size: large ? 14 : 13, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(secondary ? Theme.inactive : Theme.text)
        .padding(.horizontal, large ? 14 : 12)
        .frame(height: 36)
        .background(Theme.page, in: Capsule())
        .contentShape(Capsule())
    }
}

/// A bordered block of rows, as in Invest.dc.html.
struct AddGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.secondary.opacity(0.18)))
    }
}

/// An account menu row: icon, caption, account name and a chevron.
struct AddAccountRow: View {
    let title: String
    @Binding var selection: Int?
    let options: [Account]
    var trailing: String?

    private var account: Account? { options.first { $0.id == selection } }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { Text($0.displayName).tag(Optional($0.id)) }
            }
        } label: {
            HStack(spacing: 12) {
                let symbol = account.map { Icons.account(group: $0.group, isLiability: $0.type == "L", isInvestment: $0.isInvestment) }
                IconTile(symbol: symbol ?? "building.columns.fill", tint: account?.isInvestment == true ? Theme.invest : Theme.accent,
                         background: account?.isInvestment == true ? Theme.investTint : Theme.accentTint, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text(account?.displayName ?? "Choose").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.system(size: 13)).foregroundStyle(Theme.secondary) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("\(title): \(account?.displayName ?? "none")")
    }
}

/// Shows a graphical date picker in a popover when tapped.
struct AddDateButton<Label: View>: View {
    @Binding var date: Date
    @ViewBuilder let label: Label
    @State private var open = false

    var body: some View {
        Button { open = true } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel("Date: \(dayLabel(date, long: true))")
            .popover(isPresented: $open) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 320)
                    .padding()
                    .presentationCompactAdaptation(.popover)
                    .onChange(of: date) { _, _ in open = false }
            }
    }
}

/// iPhone: "+ Payee, note" opens an alert with the two fields. Transfers have no payee.
struct PayeeNoteChip: View {
    @Bindable var model: AddModel
    @State private var open = false

    private var hasPayee: Bool { model.kind != .transfer }

    private var text: String {
        let parts = [hasPayee ? model.payee : "", model.note].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return hasPayee ? "+ Payee, note" : "+ Note"
    }

    var body: some View {
        Button { open = true } label: {
            AddChip(text: text, secondary: model.payee.isEmpty && model.note.isEmpty)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addDetails")
        .alert(hasPayee ? "Payee and note" : "Note", isPresented: $open) {
            if hasPayee { TextField("Payee", text: $model.payee).accessibilityIdentifier("addPayee") }
            TextField("Note", text: $model.note)
            Button("Done") {}
        }
    }
}

/// iPad and Mac: payee and note rows on a grey card (iPadAdd.dc.html). Transfers have no payee.
struct PayeeNoteRows: View {
    @Bindable var model: AddModel

    var body: some View {
        VStack(spacing: 0) {
            if model.kind != .transfer {
                row("Payee", prompt: "Where you spent it", text: $model.payee).accessibilityIdentifier("addPayee")
                Divider()
            }
            row("Note", prompt: "Optional", text: $model.note)
        }
        .padding(.horizontal, 14)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).frame(width: 56, alignment: .leading)
            TextField(title, text: text, prompt: Text(prompt)).textFieldStyle(.plain).font(.system(size: 15))
        }
        .frame(height: 48)
    }
}

extension View {
    /// Keeps a sheet's bar horizontal on iPhone Duo's outer display. For a sheet whose bar holds only Cancel: a side
    /// bar there would take a column of width for one button.
    @ViewBuilder
    func horizontalBar() -> some View {
        if #available(iOS 27.1, macOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}
