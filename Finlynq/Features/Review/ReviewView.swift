import SwiftUI

/// Review imported rows one at a time (Review.dc.html on iPhone, iPadPReview.dc.html on iPad portrait, iPadReview.dc.html
/// on iPad landscape). The Mac shows the
/// two-pane bank versus Finlynq view instead (ReconcileView). Approve books the row as a transaction, Link marks it
/// as an existing one, Skip moves on without saving.
struct ReviewView: View {
    var body: some View {
        #if os(macOS)
        ReconcileView()
        #else
        ReviewQueueView()
        #endif
    }
}

#if os(iOS)
private struct ReviewQueueView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.dismiss) private var dismiss
    @State private var model = ReviewModel()
    @State private var picking = false
    /// Approve was tapped on a row with no category: approve once one is picked.
    @State private var approveAfterPick = false
    @Environment(\.presentEditor) private var present
    /// Delete asked about a bank row: it leaves the bank ledger for good.
    @State private var confirmingDelete = false

    var body: some View {
        content
            .background(Theme.page)
            .navigationTitle("Review")
            .toolbarTitleDisplayMode(.large)
            .modifier(Subtitle(text: width != .compact ? importLabel : nil))
            .toolbar {
                if width == .wide {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
                }
            }
            .task { if !model.loaded { await model.load(session) } }
            .sheet(isPresented: $picking, onDismiss: { approveAfterPick = false }, content: {
                ReviewCategoryPicker(amount: model.queue.current?.amount ?? 0, selected: model.queue.current?.categoryId) { id in
                    model.categorize(id)
                    picking = false
                    if approveAfterPick { Task { await model.approve(session) } }
                }
            })
            .confirmationDialog("Delete this bank row?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.delete(session) } }
            } message: {
                Text("It leaves your bank ledger for good, and the bank balance Finlynq compares against can change.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.loadError {
            ContentUnavailableView {
                Label("Couldn't load Review", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load(session) } }
            }
        } else if !model.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.pendingImports.isEmpty && (model.queue.rows.isEmpty || (model.queue.isDone && width == .compact)) {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text(model.queue.rows.isEmpty ? "Nothing to review. Import a statement to add transactions." : "Every row is done.")
            } actions: {
                Button("Import a statement") { present(.importStatement) }
            }
        } else if model.queue.rows.isEmpty {
            ScrollView {
                VStack(spacing: 12) {
                    pendingBanners
                    errorLine
                }
                .padding(.horizontal, width == .wide ? 28 : 20).padding(.top, 4)
                .frame(maxWidth: 640)
            }
        } else {
            switch width {
            case .compact: phone
            case .medium: portrait
            case .wide: pad
            }
        }
    }

    // MARK: Shared parts

    /// One banner per import whose rows aren't in the bank ledger yet, each with Send.
    @ViewBuilder
    private var pendingBanners: some View {
        ForEach(model.pendingImports) { item in
            PendingImportBanner(item: item, isWorking: model.isWorking) { Task { await model.send(item.id, session: session) } }
        }
    }

    /// "Chequing import, Nov 8" from the current row's account and batch date.
    private var importLabel: String? {
        guard let row = model.queue.current ?? model.queue.rows.first else { return nil }
        let account = session.accounts.first { $0.id == row.accountId }?.displayName
        let day = row.importedAt.flatMap { APIDate.parse($0) }?.formatted(.dateTime.month(.abbreviated).day())
        switch (account, day) {
        case let (account?, day?): return "\(account) import, \(day)"
        case let (account?, nil): return "\(account) import"
        default: return "From your imports"
        }
    }

    private func category(_ id: Int?) -> Category? { session.categories.first { $0.id == id } }

    private func approve() {
        guard model.queue.current?.categoryId != nil else {
            approveAfterPick = true
            picking = true
            return
        }
        Task { await model.approve(session) }
    }

    private var approveAllTitle: String {
        "Approve all \(model.queue.suggestedCount) with a suggested category"
    }

    /// Skip, Categorize and Approve in a 1 : 1.3 : 1.6 row.
    private var actions: some View {
        GeometryReader { proxy in
            let unit = (proxy.size.width - (width == .compact ? 16 : 20)) / 3.9
            HStack(spacing: width == .compact ? 8 : 10) {
                ReviewActionButton(title: "Skip", filled: false) { model.skip() }.frame(width: unit)
                ReviewActionButton(title: "Categorize", filled: false) { picking = true }.frame(width: unit * 1.3)
                ReviewActionButton(title: "Approve", filled: true) { approve() }
                    .frame(width: unit * 1.6)
                    .disabled(model.queue.needsChoice)
                    .opacity(model.queue.needsChoice ? 0.45 : 1)
                    .accessibilityHint(model.queue.needsChoice ? "Pick Link or Keep separate first" : "")
            }
        }
        .frame(height: 52)
        .disabled(model.isWorking || model.queue.isDone)
    }

    @ViewBuilder
    private var errorLine: some View {
        // Reload lists the rows again from the server, so a failed action never leaves a stale row on screen.
        if let message = model.error {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(message).font(.footnote).foregroundStyle(Theme.negative).frame(maxWidth: .infinity, alignment: .leading)
                Button("Reload") { Task { await model.reload(session) } }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).buttonStyle(.plain)
                    .disabled(model.isWorking)
            }
        }
    }

    private func card(_ row: StagedRow, wide: Bool) -> some View {
        ReviewCard(
            row: row, wide: wide, position: model.queue.position, total: model.queue.rows.count,
            account: session.accounts.first { $0.id == row.accountId }?.displayName,
            category: category(row.categoryId), needsChoice: model.queue.needsChoice,
            quick: wide ? quickCategories(for: row) : [], createsRule: Bindable(model).createsRule,
            onPick: { picking = true }, onChoose: { model.categorize($0) },
            onLink: { Task { await model.link(session) } }, onKeepSeparate: { model.keepSeparate() },
            onDelete: { confirmingDelete = true }
        )
        .disabled(model.isWorking)
    }

    /// The suggested category first, then the first few others of the same kind.
    private func quickCategories(for row: StagedRow) -> [Category] {
        let type = row.amount > 0 ? "I" : "E"
        let others = session.categories.filter { $0.type == type && $0.id != row.categoryId }.prefix(5)
        return (category(row.categoryId).map { [$0] } ?? []) + others
    }

    // MARK: iPhone

    private var phone: some View {
        ScrollView {
            VStack(spacing: 12) {
                pendingBanners
                let position = Text("\(model.queue.position) of \(model.queue.rows.count)")
                    .foregroundStyle(Theme.text).fontWeight(.semibold)
                progress(label: position + Text(importLabel.map { " · \($0)" } ?? ""), trailing: "\(model.queue.suggestedCount) suggested")
                    .padding(.horizontal, 2)
                if let row = model.queue.current { ReviewStack { card(row, wide: false) } }
                if model.queue.suggestedCount > 0 {
                    Button(approveAllTitle) { Task { await model.approveAllSuggested(session) } }
                        .font(.body.weight(.semibold)).foregroundStyle(Theme.accent).frame(height: 44)
                        .disabled(model.isWorking)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                errorLine
                actions
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(Theme.page.opacity(0.94))
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    private func progress(label: Text, trailing: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                label
                Spacer()
                Text(trailing)
            }
            .font(.footnote).foregroundStyle(Theme.secondary)
            ProgressLine(value: Double(model.queue.doneCount) / Double(max(model.queue.rows.count, 1)))
                .accessibilityLabel("\(model.queue.doneCount) of \(model.queue.rows.count) done")
        }
    }

    private func queueRow(_ row: StagedRow) -> some View {
        let outcome = model.queue.outcome(of: row.id)
        let isCurrent = row.id == model.queue.current?.id
        let name = category(row.categoryId)?.displayName ?? "No category"
        return Button { model.select(row.id) } label: {
            HStack(spacing: 10) {
                if width == .medium {  // iPadPReview's queue rows carry the category's icon.
                    let icon = category(row.categoryId).map { Icons.category($0) } ?? Icons.category(String?.none)
                    IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.14), size: 36)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.payee ?? "No payee").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(name) · \(reviewDay(row.date))").font(.footnote)
                        .foregroundStyle(outcome == nil ? (isCurrent ? Theme.inactive : Theme.secondary) : Theme.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(reviewMoney(row.amount, row.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    status(row, outcome: outcome, isCurrent: isCurrent)
                }
                .fixedSize()
            }
            .foregroundStyle(outcome == nil ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(isCurrent ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottom) { if !isCurrent { Rectangle().fill(Theme.fill).frame(height: 1).padding(.horizontal, 4) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(outcome != nil)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private func status(_ row: StagedRow, outcome: ReviewQueue.Outcome?, isCurrent: Bool) -> some View {
        switch outcome {
        case .approved?: ReviewBadge(text: "Approved", symbol: "checkmark", tint: Theme.secondary, background: Theme.fill)
        case .linked?: ReviewBadge(text: "Linked", symbol: "link", tint: Theme.secondary, background: Theme.fill)
        case nil:
            if model.queue.isBlocked(row) {
                ReviewBadge(text: "Possible match", tint: Theme.accent,
                      background: isCurrent ? Theme.card : Theme.accentTint)
            } else if row.categoryId == nil {
                ReviewBadge(text: "Needs category", tint: Theme.warning, background: Theme.warningTint)
            } else {
                ReviewBadge(text: "Suggested", tint: Theme.positive, background: Theme.positiveTint)
            }
        }
    }

    private func nextUp(_ row: StagedRow) -> some View {
        HStack(spacing: 10) {
            Text("Next up")
            Text("\(row.payee ?? "No payee") \(reviewMoney(row.amount, row.currency))").foregroundStyle(Theme.text).fontWeight(.semibold)
            if let name = category(row.categoryId)?.displayName { Text("\(name), suggested") }
        }
        .font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4).lineLimit(1)
    }
}

extension ReviewQueueView {
    // MARK: iPad

    private var approveAll: some View {
        Button { Task { await model.approveAllSuggested(session) } } label: {
            Text(approveAllTitle).font(.subheadline.weight(.semibold)).foregroundStyle(width == .wide ? .white : Theme.accent)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(width == .wide ? Theme.accent : Theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
    }

    private var padProgress: some View {
        let waiting = model.queue.needsCategoryCount
        let done = Text("\(model.queue.doneCount) of \(model.queue.rows.count) done").foregroundStyle(Theme.text).fontWeight(.semibold)
        let needs = waiting > 0 ? " · \(waiting) need\(waiting == 1 ? "s" : "") a category" : ""
        return progress(label: done, trailing: "\(model.queue.suggestedCount) suggested" + needs).padding(.horizontal, 4).padding(.top, 2)
    }

    @ViewBuilder
    private var current: some View {
        if let row = model.queue.current {
            ReviewStack { card(row, wide: true) }
            errorLine
            actions
            if let next = model.queue.next { nextUp(next) }
        } else {
            ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("Every row is done."))
                .padding(.vertical, 40)
        }
    }

    private var queueRows: some View {
        VStack(spacing: 0) {
            ForEach(model.queue.rows) { row in queueRow(row) }
        }
        .padding(6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// iPadPReview: one column with the card first, then the queue below it.
    private var portrait: some View {
        ScrollView {
            VStack(spacing: 14) {
                pendingBanners
                padProgress
                current
                if model.queue.suggestedCount > 0 { approveAll }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Queue").font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(model.queue.rows.count) rows").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 4)
                    queueRows
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
        }
    }

    private var pad: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 12) {
                pendingBanners
                if model.queue.suggestedCount > 0 { approveAll }
                padProgress
                ScrollView { queueRows }
            }
            .padding(.leading, 28).padding(.trailing, 16).padding(.bottom, 28)
            .containerRelativeFrame(.horizontal) { length, _ in length * 0.44 }
            Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea(edges: .bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { current }
                    .padding(.leading, 24).padding(.trailing, 28).padding(.bottom, 28)
            }
        }
        .padding(.top, 8)
    }
}

/// The navigation subtitle where the system has one (iPadOS 26).
private struct Subtitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if #available(iOS 26, *), let text { content.navigationSubtitle(text) } else { content }
    }
}
#endif

private struct ReviewActionButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? .white : Theme.text)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(filled ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// "6 rows from chequing-nov.csv aren't in your bank ledger yet" with Send, and the server's reasons for rows a
/// previous send left behind.
private struct PendingImportBanner: View {
    let item: PendingImport
    let isWorking: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconTile(symbol: "tray.and.arrow.down", size: 34)
                Text(item.banner)
                    .font(.subheadline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                Button("Send", action: onSend)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Theme.accent, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityHint("Adds the rows to your bank ledger so you can review them")
            }
            if !item.errors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.errors.prefix(3), id: \.self) { Text($0) }
                    if item.errors.count > 3 { Text("and \(item.errors.count - 3) more") }
                }
                .font(.footnote).foregroundStyle(Theme.negative)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
