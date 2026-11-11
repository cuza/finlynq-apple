import SwiftUI

/// A system segmented control over a list of options (Plan's Budget/Bills/Goals, Insights' periods).
struct SegmentBar<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value

    init(_ title: String, options: [(Value, String)], selection: Binding<Value>) {
        self.title = title
        self.options = options
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented).labelsHidden()
    }
}

/// Round-ended chip: black when active, white with a hairline otherwise (Plan.dc.html filters, Statement.dc.html ranges).
struct FilterChip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 13).frame(height: 30)
                .foregroundStyle(active ? Theme.page : Theme.text)
                .background(active ? Theme.text : Theme.card, in: Capsule())
                .overlay { if !active { Capsule().strokeBorder(Theme.hairline) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// White capsule in a page header: a month stepper or "+ Add bill" (Plan.dc.html, Bills.dc.html).
struct HeaderPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .padding(.horizontal, 4)
            .frame(height: 40)
            .background(Theme.card, in: Capsule())
    }
}

/// "‹ November ›": steps a month back or forward.
struct MonthStepper: View {
    @Binding var month: Date
    var format: Date.FormatStyle = .dateTime.month(.wide)

    var body: some View {
        HeaderPill {
            Button { step(-1) } label: { chevron("chevron.left") }.accessibilityLabel("Previous month").keyboardShortcut("[")
            Text(month.formatted(format)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .monospacedDigit().fixedSize()
            Button { step(1) } label: { chevron("chevron.right") }.accessibilityLabel("Next month").keyboardShortcut("]")
        }
        .buttonStyle(.plain)
    }

    private func chevron(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func step(_ months: Int) { month = Self.step(month, by: months) }

    static func step(_ month: Date, by months: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: month) ?? month
    }
}

/// The month stepper as system toolbar items: ‹ November ›.
struct MonthStepperItems: ToolbarContent {
    @Binding var month: Date
    var format: Date.FormatStyle = .dateTime.month(.wide)

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Previous month", systemImage: "chevron.left") { month = MonthStepper.step(month, by: -1) }.keyboardShortcut("[")
            Text(month.formatted(format)).monospacedDigit().fixedSize()
            Button("Next month", systemImage: "chevron.right") { month = MonthStepper.step(month, by: 1) }.keyboardShortcut("]")
        }
    }
}

/// An inline error with a Retry button, for a source that failed while the rest of the screen loaded.
/// At least 44pt tall, so Retry is a full-size tap target.
struct InlineError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
            Text(message).foregroundStyle(Theme.secondary)
            Spacer(minLength: 4)
            Button("Retry", action: retry).buttonStyle(.borderless).foregroundStyle(Theme.accent)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// A pushed page's bar: the system large title and a trailing control.
/// Off for an embedded pane, so it doesn't replace its host's title.
struct PushedPageBar<Trailing: View>: ViewModifier {
    let enabled: Bool
    let title: String
    @ViewBuilder let trailing: Trailing

    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(title)
            #if os(iOS)
                .toolbarTitleDisplayMode(.large)
                .toolbar { ToolbarItem(placement: .primaryAction) { trailing } }
            #endif
        } else {
            content
        }
    }
}
