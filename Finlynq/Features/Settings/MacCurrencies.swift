import SwiftUI

/// The rate line beside a currency, such as "1 CAD = 0.72 USD", or the other way round when inverted.
enum RateText {
    /// `rate` turns one `code` into the display currency.
    static func line(code: String, display: String, rate: Double, inverted: Bool) -> String {
        guard rate > 0 else { return "" }
        let format = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...4))
        return inverted
            ? "1 \(display) = \((1 / rate).formatted(format)) \(code)"
            : "1 \(code) = \(rate.formatted(format)) \(display)"
    }
}

#if os(macOS)
/// "Currencies you use" with add and remove, each with its rate to the display currency, and "Show exchange rates"
/// (MacSettings.dc.html). The shared demo is read-only.
struct MacCurrencies: View {
    @Environment(Session.self) private var session
    @State private var codes: [String]?
    @State private var failed = false
    @State private var rates: [String: Double] = [:]
    @State private var inverted: Bool?
    @State private var selected: String?
    @State private var removing: String?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        LabeledContent("Currencies you use:") {
            VStack(alignment: .leading, spacing: 5) {
                if let codes {
                    list(codes)
                } else if failed {
                    InlineError(message: "Couldn't load your currencies.") { failed = false; attempt += 1 }.frame(width: 300)
                } else {
                    ProgressView().controlSize(.small)
                }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative) }
            }
        }
        LabeledContent("Show exchange rates:") {
            VStack(alignment: .leading, spacing: 5) {
                let shown = Binding { inverted ?? false } set: { value in Task { await setInverted(value) } }
                Picker("Show exchange rates", selection: shown) {
                    Text("As quoted").tag(false)
                    Text("Inverted").tag(true)
                }
                .labelsHidden().frame(width: 200)
                .disabled(inverted == nil || session.isDemo)
                MacNote("Custom rates are on the web.")
            }
        }
        .task(id: "\(session.revision)|\(attempt)") { await load() }
        .confirmationDialog("Stop using \(removing ?? "")?", isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
                            titleVisibility: .visible) {
            Button("Remove \(removing ?? "")", role: .destructive) {
                if let code = removing { Task { await save(codes?.filter { $0 != code }) } }
            }
        } message: {
            Text("Accounts in it keep their amounts. It just leaves this list.")
        }
    }

    private func list(_ codes: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(codes, id: \.self) { code in
                HStack {
                    Text("\(code) \(Text(CurrencyList.name(code)).foregroundStyle(Theme.secondary))")
                    Spacer()
                    Text(code == session.currency ? "Display" : rates[code].map {
                        RateText.line(code: code, display: session.currency, rate: $0, inverted: inverted ?? false)
                    } ?? "")
                    .foregroundStyle(Theme.secondary)
                }
                .frame(height: 26).padding(.horizontal, 10)
                .background(selected == code ? Theme.accentTint : .clear)
                .contentShape(Rectangle())
                .onTapGesture { selected = code }
                .accessibilityAddTraits(selected == code ? [.isButton, .isSelected] : .isButton)
                Divider()
            }
            HStack(spacing: 0) {
                Menu {
                    ForEach(CurrencyList.codes.filter { !codes.contains($0) }, id: \.self) { code in
                        Button("\(code), \(CurrencyList.name(code))") { Task { await save(codes + [code]) } }
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 26, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Add currency")
                Divider().frame(height: 22)
                Button { removing = selected } label: { Image(systemName: "minus").frame(width: 26, height: 22) }
                    .buttonStyle(.borderless)
                    .disabled(selected == nil || selected == session.currency || codes.count < 2)
                    .accessibilityLabel("Remove currency")
                Divider().frame(height: 22)
                Spacer()
            }
            .background(Theme.toolbar)
            .disabled(session.isDemo)
        }
        .frame(width: 300)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.badge))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func load() async {
        async let codes = optionalLoad("active currencies") { try await session.api.activeCurrencies() }
        async let rates = optionalLoad("fx rates") { try await session.api.fxRates(target: session.currency) }
        async let inverted = optionalLoad("fx rate view") { try await session.api.fxRatesInverted() }
        self.codes = await codes
        failed = self.codes == nil
        self.rates = await rates ?? [:]
        self.inverted = await inverted
    }

    private func save(_ list: [String]?) async {
        guard let list, !list.isEmpty, !session.isDemo else { return }
        do {
            codes = try await session.api.setActiveCurrencies(list)
            selected = nil
            error = nil
            // An added currency has no rate until the rates load again.
            if let fresh = await optionalLoad("fx rates", { try await session.api.fxRates(target: session.currency) }) {
                rates = fresh
            }
        } catch {
            self.error = "Couldn't save your currencies. \(error.localizedDescription)"
        }
    }

    private func setInverted(_ value: Bool) async {
        guard !session.isDemo else { return }
        let before = inverted
        inverted = value
        do {
            try await session.api.setFxRatesInverted(value)
            error = nil
        } catch {
            inverted = before
            self.error = "Couldn't change how rates show. \(error.localizedDescription)"
        }
    }
}
#endif
