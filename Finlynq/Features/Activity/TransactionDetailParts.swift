import SwiftUI

/// Tags as pills; tapping them edits the comma separated text.
struct TagsField: View {
    @Binding var tags: String
    let compact: Bool
    @FocusState private var editing: Bool

    var body: some View {
        let list = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if editing || list.isEmpty {
            TextField("Comma separated", text: $tags).textFieldStyle(.plain).focused($editing)
        } else {
            Button { editing = true } label: {
                HStack(spacing: compact ? 4 : 6) {
                    ForEach(list, id: \.self) { tag in
                        if compact {
                            Text(tag).font(.system(size: 12)).padding(.horizontal, 6)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
                        } else {
                            Text(tag).font(.footnote.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Theme.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tags: \(list.joined(separator: ", "))")
        }
    }
}

/// "Create a rule for <payee>" with its Create button.
struct RuleRow: View {
    let name: String
    let category: String
    let compact: Bool
    let created: Bool
    let create: () -> Void

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            IconTile(symbol: "wand.and.stars", size: compact ? 28 : 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Create a rule for \(name)").fontWeight(.semibold).foregroundStyle(Theme.text)
                Text("Payee contains \"\(name)\", set \(category)").font(DetailFont.small).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            if created {
                Chip(text: "Created", tint: Theme.positive, background: Theme.positiveTint)
            } else {
                Button(action: create) {
                    if compact {
                        Text("Create").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline))
                    } else {
                        Text("Create").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12).frame(height: 32).background(Theme.accentTint, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// How often this payee shows up this year, and the average amount.
struct SimilarRow: View {
    let payee: String
    let stats: (count: Int, average: Double)
    let currency: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("All \(payee) transactions").fontWeight(compact ? .medium : .semibold).foregroundStyle(Theme.text)
            Text("\(stats.count) this year · avg \(stats.average.money(currency))")
                .font(DetailFont.small).foregroundStyle(Theme.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Save (the iPhone page saves from the toolbar instead) and Delete, styled per layout.
struct DetailFooter: View {
    let layout: TransactionDetailView.Layout
    let dirty: Bool
    let saving: Bool
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let compact = layout == .inspector
        if layout != .page && dirty {
            Button(action: onSave) {
                Text("Save changes").fontWeight(.semibold).frame(maxWidth: compact ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(saving)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .trailing)
        }
        switch layout {
        case .page:
            Button(action: onDelete) {
                Text("Delete transaction").font(.callout.weight(.semibold)).foregroundStyle(Theme.negative)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        case .pane:
            Button(action: onDelete) {
                Text("Delete transaction").fontWeight(.semibold).foregroundStyle(Theme.negative)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .inspector:
            Button(action: onDelete) {
                Text("Delete transaction").fontWeight(.medium).foregroundStyle(Theme.negative)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.negative.opacity(0.3)))
            }
            .buttonStyle(.plain)
        }
    }
}

enum DetailFont {
    /// 15pt on iOS, 13pt on the Mac.
    static var body: Font {
        #if os(macOS)
        .body
        #else
        .subheadline
        #endif
    }

    /// 13pt on iOS, 12pt on the Mac.
    static var small: Font {
        #if os(macOS)
        .callout
        #else
        .footnote
        #endif
    }
}

extension Theme {
    /// The Mac inspector's background (#FAFAFB); the page grey elsewhere.
    static var toolbarBackground: Color {
        #if os(macOS)
        toolbar
        #else
        page
        #endif
    }
}

/// White card in the detail: 18pt corners on iOS; 10pt with a light outline in the Mac inspector.
struct DetailCard: ViewModifier {
    let radius: CGFloat
    let bordered: Bool

    func body(content: Content) -> some View {
        if bordered {
            content.background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.7)))
        } else {
            content.listCard(radius: radius)
        }
    }
}

/// The pushed screen's large payee title and Save button. Embedded layouts leave the host's title alone.
struct PageChrome: ViewModifier {
    let title: String?
    let dirty: Bool
    let saving: Bool
    let save: () -> Void

    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                #if os(iOS)
                .toolbarTitleDisplayMode(.large)
                #endif
                .toolbar {
                    if dirty {
                        ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(saving) }
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// A menu that draws only its label, without the button chrome or tint.
    func plainMenu() -> some View { menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden) }
}

/// Loads a transaction by id for routes that carry only the id, and reloads it after an edit.
struct TransactionByID: View {
    @Environment(Session.self) private var session
    let id: Int
    @State private var transaction: Transaction?
    @State private var missing = false
    @State private var error: String?

    var body: some View {
        Group {
            if let transaction {
                TransactionDetailView(transaction: transaction, embedded: false) { Task { await load() } }.id(transaction)
            } else if missing {
                EmptyState(title: "Transaction not found", message: "It may have been deleted.", symbol: "questionmark.circle")
            } else if let error {
                EmptyState(title: "Couldn't load", message: error, symbol: "exclamationmark.triangle")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.page)
        .navigationTitle(transaction?.title ?? "Transaction")
        .task { await load() }
    }

    private func load() async {
        do {
            let row = try await session.api.transaction(id: id)
            transaction = row
            missing = row == nil
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
