import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Fields for the CSV exports (Activity, income statement, tax, holdings, loan schedule).
nonisolated enum CSV {
    /// A field as is, or quoted with its quotes doubled when it holds a comma, quote or line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A text field (a payee, category or name). A leading `'` when it starts with `=`, `+`, `-`, `@`, tab or
    /// carriage return, so a spreadsheet reads it as text instead of a formula; then quoted like `field`.
    static func text(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return field(value) }
        return field("'" + value)
    }

    /// A number with a dot and `digits` decimals, whatever the locale.
    static func number(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// CSV text for `fileExporter`.
struct CSVFile: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// A CSV file to share, written to a temporary file when shared.
struct CSVExport: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.name)
            try Data(export.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
