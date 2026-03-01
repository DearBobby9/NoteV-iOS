import SwiftUI

// MARK: - CourseBadge

/// Small colored badge showing course name. Used in recording and session list.
struct CourseBadge: View {
    let name: String
    let colorHex: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: parseHex(colorHex)))
                .frame(width: 6, height: 6)

            Text(name)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(Color(hex: parseHex(colorHex)))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(hex: parseHex(colorHex)).opacity(0.15))
        .cornerRadius(10)
    }

    private func parseHex(_ hex: String) -> UInt {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        return UInt(value)
    }
}
