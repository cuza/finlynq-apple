import SwiftUI

extension View {
    /// Fills its column, but reports `width` as its ideal width. Inside `ViewThatFits(in: .horizontal)` this view is
    /// picked only when the column is at least that wide, and the next option otherwise. Screens use it to show two
    /// columns on iPhone Duo's open display (669pt) while an iPad portrait column (540pt) gets one.
    func wideEnough(_ width: CGFloat) -> some View {
        frame(minWidth: width, idealWidth: width, maxWidth: .infinity, alignment: .topLeading)
    }
}
