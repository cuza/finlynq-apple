import SwiftUI
import UniformTypeIdentifiers

/// Import a bank statement (Import.dc.html): pick the account and a CSV, OFX or QFX file, check the preview, then
/// upload. The server books what the account's rules match; the rest waits in Review.
struct ImportSheet: View {
    /// A file dropped on the window, opened as soon as the sheet appears.
    var droppedURL: URL?
    /// A file to open as soon as the sheet appears (debug screenshots).
    var sample: UploadFile?
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model = ImportModel()
    @State private var choosing = false
    @State private var showAll = false
    @State private var email: String?
    @State private var copied = false
    /// The sheet's width, nil until measured. A phone-width sheet shows the preview's dates in a column; a wider one
    /// (iPadPImport) puts each date under its payee.
    @State private var width: CGFloat?
    @Environment(\.shellSizeClass) private var sizeClass
    private var datesBelow: Bool {
        #if os(iOS)
        LayoutWidth(measured: width, typeSize: .large, sizeClass: sizeClass) != .compact
        #else
        false
        #endif
    }

    static let types: [UTType] = [.commaSeparatedText] + ["ofx", "qfx"].compactMap { UTType(filenameExtension: $0) }

    private var accounts: [Account] { session.accounts.filter { !$0.archived } }
    private var account: Account? { accounts.first { $0.id == model.accountId } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sourceCard
                    Text("Works with CSV, OFX and QFX files from your bank.")
                        .font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 4).padding(.top, -4)
                    if !model.columns.isEmpty { columnsCard }
                    if let summary = model.summary { previewCard(summary) }
                    if let message = model.error {
                        Text(message).font(.footnote).foregroundStyle(Theme.negative).padding(.horizontal, 4)
                            .accessibilityIdentifier("importError")
                    }
                    primaryButton
                    Text(footnote).font(.caption).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, -4)
                    if let email { emailCard(email) }
                }
                .padding(.horizontal, 20).padding(.bottom, 28).padding(.top, 2)
            }
        }
        .background(Theme.page)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #if os(macOS)
        .frame(width: 440, height: 720)
        #endif
        .fileImporter(isPresented: $choosing, allowedContentTypes: Self.types) { result in
            switch result {
            case .success(let url): Task { await model.pick(url: url, api: session.api, accountName: account?.name ?? account?.alias) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await model.pick(url: url, api: session.api, accountName: account?.name ?? account?.alias) }
            return true
        }
        .onChange(of: accounts.map(\.id), initial: true) {
            // Accounts can arrive after the sheet opens, right after launch.
            if model.accountId == nil { model.accountId = accounts.first { !$0.isInvestment }?.id ?? accounts.first?.id }
        }
        .task {
            if let sample { await model.pick(sample, api: session.api, accountName: account?.name ?? account?.alias) }
            if let droppedURL { await model.pick(url: droppedURL, api: session.api, accountName: account?.name ?? account?.alias) }
            email = try? await session.api.importEmailAddress()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            #if os(iOS)
            Capsule().fill(Theme.hairline).frame(width: 40, height: 5).accessibilityHidden(true)
            #endif
            ZStack {
                Text("Import statement").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                HStack {
                    Button("Cancel") { dismiss() }.font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.accent)
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: Sections

    private var sourceCard: some View {
        VStack(spacing: 0) {
            Menu {
                Picker("Into account", selection: $model.accountId) {
                    ForEach(accounts) { Text($0.displayName).tag(Optional($0.id)) }
                }
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "building.columns", size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Into account").font(.footnote).foregroundStyle(Theme.secondary)
                        Text(account?.displayName ?? "Choose an account").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.secondary.opacity(0.7))
                }
                .frame(minHeight: 52).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain)
            .onChange(of: model.accountId) { old, _ in
                // A CSV without an Account column was previewed for the old account; preview it again.
                if old != nil, let file = model.file {
                    Task { await model.pick(file, api: session.api, accountName: account?.name ?? account?.alias) }
                }
            }
            divider
            fileRow
            divider
            HStack(spacing: 12) {
                (Text("Ending balance ") + Text("(optional)").font(.footnote)).font(.subheadline).foregroundStyle(Theme.secondary)
                    .lineLimit(1).fixedSize()
                Spacer()
                TextField(0.0.money(account?.currency), text: $model.endingBalance)
                    .multilineTextAlignment(.trailing).font(.subheadline.weight(.semibold)).frame(width: 120)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Ending balance, optional")
            }
            .frame(minHeight: 50)
        }
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var divider: some View { Rectangle().fill(Theme.fill).frame(height: 1) }

    private var fileRow: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "doc.text", tint: Theme.positive, background: Theme.positiveTint, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                if let file = model.file {
                    Text(file.filename).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).truncationMode(.middle)
                    Text(fileDetail).font(.footnote).foregroundStyle(Theme.secondary)
                } else {
                    Text("No file yet").fontWeight(.semibold).foregroundStyle(Theme.text)
                    #if os(macOS)
                    Text("Choose one or drop it here").font(.footnote).foregroundStyle(Theme.secondary)
                    #endif
                }
            }
            Spacer()
            if model.isWorking { ProgressView().controlSize(.small) }
            Button(model.file == nil ? "Choose file" : "Change file") { choosing = true }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).frame(height: 32)
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .contentShape(Capsule())
                .buttonStyle(.plain)
        }
        .frame(minHeight: 52)
    }

    /// "46 rows · Oct 10 to Nov 8".
    private var fileDetail: String {
        guard let summary = model.summary else { return model.isWorking ? "Reading…" : "" }
        var parts = ["\(summary.total) row\(summary.total == 1 ? "" : "s")"]
        if let first = summary.firstDate, let last = summary.lastDate { parts.append("\(reviewDay(first)) to \(reviewDay(last))") }
        return parts.joined(separator: " · ")
    }

    private var columnsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Columns").font(.system(size: 15, weight: .bold)).frame(height: 32)
            ReviewFlow(spacing: 6) {
                ForEach(model.columns, id: \.self) { name in
                    Text(name).font(.footnote.weight(.medium)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Text("Detected from the file").font(.footnote).foregroundStyle(Theme.secondary).padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func previewCard(_ summary: ImportModel.Summary) -> some View {
        // Collapsed: the two newest new rows and the newest duplicate, so both kinds show.
        let fresh = summary.lines.filter { !$0.isDuplicate }.prefix(summary.duplicates > 0 ? 2 : 3)
        let sample = (Array(fresh) + summary.lines.filter(\.isDuplicate).prefix(1)).sorted { $0.date > $1.date }
        let lines = showAll ? summary.lines : sample
        return VStack(alignment: .leading, spacing: 0) {
            Text("Preview").font(.system(size: 15, weight: .bold)).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 12) {
                    if !datesBelow {
                        Text(reviewDay(line.date)).font(.footnote).foregroundStyle(Theme.secondary).frame(width: 44, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(line.payee).font(.subheadline.weight(.semibold)).lineLimit(1)
                        let note = [datesBelow ? reviewDay(line.date) : nil, line.isDuplicate ? "Already in Finlynq" : nil]
                            .compactMap { $0 }
                        if !note.isEmpty { Text(note.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.secondary) }
                    }
                    Spacer()
                    Text(reviewMoney(line.amount, account?.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .fixedSize()
                }
                .foregroundStyle(line.isDuplicate ? Theme.secondary : Theme.text)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { divider }
            }
            if summary.duplicates > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "square.on.square").font(.system(size: 15)).foregroundStyle(Theme.positive)
                    (Text("\(summary.duplicates) already in Finlynq").fontWeight(.semibold) + Text(", will be skipped"))
                        .font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer()
                    Button(showAll ? "Hide" : "Show") { showAll.toggle() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            } else if summary.lines.count > 3 {
                Button(showAll ? "Show fewer" : "Show all \(summary.lines.count)") { showAll.toggle() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).buttonStyle(.plain)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Import

    private var primaryButton: some View {
        Button {
            if model.result != nil { dismiss(); return }
            Task {
                if await model.upload(api: session.api) { await session.didSave() }
            }
        } label: {
            Group {
                if model.isWorking && model.summary != nil { ProgressView().tint(.white) } else { Text(primaryTitle) }
            }
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.result == nil && (model.summary == nil || model.accountId == nil || model.isWorking))
        .opacity(model.result == nil && model.summary == nil ? 0.45 : 1)
        .accessibilityIdentifier("importButton")
    }

    private var primaryTitle: String {
        if model.result != nil { return "Done" }
        guard let summary = model.summary else { return "Import" }
        return "Import \(summary.importable) transaction\(summary.importable == 1 ? "" : "s")"
    }

    private var footnote: String {
        guard let result = model.result else { return "Rules categorize what they can. The rest goes to Review." }
        let added = result.counts?.new ?? model.summary?.importable ?? 0
        let skipped = result.counts?.skippedDuplicate ?? 0
        return "Imported \(added). " + (skipped > 0 ? "\(skipped) already in Finlynq were skipped. " : "") + "Check Review for the rest."
    }

    private func emailCard(_ address: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope").font(.system(size: 17)).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Or forward statements to").font(.footnote).foregroundStyle(Theme.secondary)
                Text(address).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                #if os(iOS)
                UIPasteboard.general.string = address
                #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                #endif
                copied = true
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Theme.accentTint, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityLabel("Copy import email address")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    /// Mac: dropping a statement file on the screen opens the import sheet with it.
    func importsDroppedStatements() -> some View { modifier(StatementDrop()) }
}

private struct StatementDrop: ViewModifier {
    @State private var dropped: DroppedFile?

    private struct DroppedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                dropped = DroppedFile(url: url)
                return true
            }
            .sheet(item: $dropped) { ImportSheet(droppedURL: $0.url) }
        #else
        content
        #endif
    }
}
