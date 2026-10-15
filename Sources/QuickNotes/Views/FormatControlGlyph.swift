import SwiftUI

struct FormatControlGlyph: View {
    let symbol: String

    static func symbol(for label: String) -> String? {
        switch label {
        case "Bold": return "bold"
        case "Italic": return "italic"
        case "Underline": return "underline"
        case "Strikethrough": return "strikethrough"
        default: return nil
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}
