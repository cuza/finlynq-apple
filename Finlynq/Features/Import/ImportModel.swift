import Foundation
import OSLog

/// The import sheet's state (Import.dc.html): pick an account and a statement, preview it, then upload it.
/// The upload goes through `POST /api/import/staging/upload`, like the web Import page: the server runs the
/// account's rules and what they don't book waits in Review.
@Observable
final class ImportModel {
    static let extensions = ["csv", "ofx", "qfx"]
    static let wrongType = "Finlynq imports CSV, OFX and QFX files"

    var accountId: Int?
    private(set) var file: UploadFile?
    private(set) var summary: Summary?
    /// The CSV columns the server read: date, payee and amount header names.
    private(set) var columns: [String] = []
    var endingBalance = ""
    var error: String?
    private(set) var isWorking = false
    private(set) var result: StagingUploadResult?

    private static let log = Logger(subsystem: "dev.cuza.finlynq", category: "import")

    /// An error message for a file Finlynq can't import, or nil.
    static func check(filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        return extensions.contains(ext) ? nil : wrongType
    }

    /// Reads a picked or dropped file. A security-scoped URL (from the file importer) is opened for the read.
    func pick(url: URL, api: APIClient, accountName: String?) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let message = Self.check(filename: url.lastPathComponent) {
            error = message
            return
        }
        do {
            let data = try Data(contentsOf: url)
            await pick(UploadFile(filename: url.lastPathComponent, data: data), api: api, accountName: accountName)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Parses the file on the server without saving it. A bank CSV with no Account column comes back unmapped, so
    /// it is parsed again with its date, payee and amount columns and the chosen account as the default.
    func pick(_ file: UploadFile, api: APIClient, accountName: String?) async {
        if let message = Self.check(filename: file.filename) {
            error = message
            return
        }
        self.file = file
        summary = nil
        columns = []
        result = nil
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            var preview = try await api.importPreview(file: file)
            if preview.type.hasPrefix("csv"), (preview.valid ?? []).isEmpty, (preview.duplicates ?? []).isEmpty {
                guard let mapping = preview.suggestedMapping ?? Self.detectMapping(headers: preview.headers ?? []) else {
                    error = "Finlynq couldn't find the date and amount columns in this file."
                    return
                }
                preview = try await api.importMapCSV(file: file, mapping: mapping, defaultAccount: accountName)
                columns = [mapping.date, mapping.payee, mapping.amount].compactMap(\.self)
            } else if preview.type == "csv" {
                columns = preview.headers ?? []
            }
            summary = Summary(preview)
        } catch {
            Self.log.error("import preview failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    /// Uploads the statement. Returns true when the server took it.
    func upload(api: APIClient) async -> Bool {
        guard let file, let accountId else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            result = try await api.uploadStatement(file: file, accountId: accountId, statementBalance: Self.amount(endingBalance))
            return true
        } catch {
            Self.log.error("import upload failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return false
        }
    }

    /// "$9,058.05", "-12.5" or "9.058,05 €" as a number, read like a typed amount (`BudgetModel.amount`) after the
    /// currency sign and a minus sign come off; nil when empty or not a number.
    static func amount(_ text: String, locale: Locale = .current) -> Double? {
        let text = text.replacingOccurrences(of: "\u{2212}", with: "-")
        guard let value = BudgetModel.amount(text.filter { $0.isNumber || $0 == "." || $0 == "," }, locale: locale) else { return nil }
        return text.contains("-") ? -value : value
    }

    // ponytail: header-name match like the server's autoDetectColumnMapping; the user can't change it in the app.
    /// Date, amount and payee columns found by header name, or nil without a date or amount column.
    static func detectMapping(headers: [String]) -> ColumnMapping? {
        func find(_ keys: [String]) -> String? { headers.first { header in keys.contains { header.lowercased().contains($0) } } }
        guard let date = find(["date"]), let amount = find(["amount", "debit", "credit"]) else { return nil }
        return ColumnMapping(date: date, amount: amount, payee: find(["payee", "description", "merchant", "name", "memo"]))
    }

    struct Line: Hashable {
        let date: String
        let payee: String
        let amount: Double
        let isDuplicate: Bool
    }

    /// What the preview found. OFX and QFX previews don't check for duplicates; the server skips them on upload.
    struct Summary {
        let importable: Int
        let duplicates: Int
        /// Every row, newest first.
        let lines: [Line]
        var total: Int { importable + duplicates }
        var firstDate: String? { lines.last?.date }
        var lastDate: String? { lines.first?.date }

        init(_ preview: ImportPreview) {
            let fresh = (preview.valid ?? []).map { Line(date: $0.date, payee: $0.payee, amount: $0.amount, isDuplicate: false) }
                + (preview.transactions ?? []).map { Line(date: $0.date, payee: $0.payee, amount: $0.amount, isDuplicate: false) }
            let copies = (preview.duplicates ?? []).map { Line(date: $0.date, payee: $0.payee, amount: $0.amount, isDuplicate: true) }
            importable = fresh.count
            duplicates = copies.count
            lines = (fresh + copies).enumerated()
                .sorted { ($0.element.date, $1.offset) > ($1.element.date, $0.offset) }
                .map(\.element)
        }
    }
}
