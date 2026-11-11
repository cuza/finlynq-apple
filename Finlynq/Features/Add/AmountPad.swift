import SwiftUI

/// The iPhone number pad (Add.dc.html): 3 by 4 grey keys with a backspace key.
struct AmountPad: View {
    enum Key: Hashable {
        case digit(Int), dot, backspace
    }

    let onPress: (Key) -> Void

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)], [.digit(4), .digit(5), .digit(6)], [.digit(7), .digit(8), .digit(9)],
        [.dot, .digit(0), .backspace]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button { onPress(key) } label: {
                            label(key).font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Theme.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name(key))
                    }
                }
            }
        }
    }

    @ViewBuilder private func label(_ key: Key) -> some View {
        switch key {
        case .digit(let digit): Text(String(digit))
        case .dot: Text(".")
        case .backspace: Image(systemName: "delete.left")
        }
    }

    private func name(_ key: Key) -> String {
        switch key {
        case .digit(let digit): String(digit)
        case .dot: "Decimal point"
        case .backspace: "Delete"
        }
    }
}
