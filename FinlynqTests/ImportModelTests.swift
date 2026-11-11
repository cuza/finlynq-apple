import Foundation
import Testing
@testable import Finlynq

struct ImportModelTests {
    @Test func importRejectsOtherExtensions() {
        #expect(ImportModel.check(filename: "statement.pdf") == "Finlynq imports CSV, OFX and QFX files")
        #expect(ImportModel.check(filename: "statement") == "Finlynq imports CSV, OFX and QFX files")
        #expect(ImportModel.check(filename: "chequing-nov.CSV") == nil)
        #expect(ImportModel.check(filename: "a.ofx") == nil)
        #expect(ImportModel.check(filename: "a.qfx") == nil)
    }

    @Test func csvPreviewCountsRowsAndDuplicates() throws {
        let json = #"""
        {"type":"csv","headers":["Date","Description","Amount"],
        "valid":[{"date":"2026-11-08","account":"Chequing","amount":-27.99,"payee":"AMZN Mktp CA"},
                 {"date":"2026-10-10","account":"Chequing","amount":-500,"payee":"Transfer to Savings"}],
        "duplicates":[{"date":"2026-11-03","account":"Chequing","amount":-1450,"payee":"Maple Leaf Properties"}],
        "errors":[]}
        """#
        let preview = try JSONDecoder().decode(ImportPreview.self, from: Data(json.utf8))
        let summary = ImportModel.Summary(preview)
        #expect(summary.importable == 2)
        #expect(summary.duplicates == 1)
        #expect(summary.total == 3)
        #expect(summary.lines.map(\.payee) == ["AMZN Mktp CA", "Maple Leaf Properties", "Transfer to Savings"], "newest first")
        #expect(summary.lines.map(\.isDuplicate) == [false, true, false])
        #expect(summary.firstDate == "2026-10-10")
        #expect(summary.lastDate == "2026-11-08")
    }

    @Test func ofxPreviewHasNoDuplicateCount() throws {
        let json = #"{"type":"ofx","transactions":[{"date":"2026-11-01","amount":3200,"payee":"Acme"}]}"#
        let preview = try JSONDecoder().decode(ImportPreview.self, from: Data(json.utf8))
        let summary = ImportModel.Summary(preview)
        #expect(summary.importable == 1)
        #expect(summary.duplicates == 0)
        #expect(summary.lines.first?.amount == 3200)
    }

    @Test func detectsBankColumns() {
        let mapping = ImportModel.detectMapping(headers: ["Transaction Date", "Description", "Amount", "Balance"])
        #expect(mapping?.date == "Transaction Date")
        #expect(mapping?.payee == "Description")
        #expect(mapping?.amount == "Amount")
        #expect(ImportModel.detectMapping(headers: ["Foo", "Bar"]) == nil)
    }

    @Test func endingBalanceReadsSignsSymbolsAndTheLocale() {
        let english = Locale(identifier: "en_US")
        #expect(ImportModel.amount("$9,058.05", locale: english) == 9058.05)
        #expect(ImportModel.amount("\u{2212}12.5", locale: english) == -12.5)
        #expect(ImportModel.amount("-1,234", locale: english) == -1234)
        #expect(ImportModel.amount("9.058,05 \u{20AC}", locale: Locale(identifier: "de_DE")) == 9058.05)
        #expect(ImportModel.amount("", locale: english) == nil)
        #expect(ImportModel.amount("n/a", locale: english) == nil)
    }
}
