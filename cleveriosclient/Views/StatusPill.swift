import SwiftUI

struct StatusPill: View {
    let text: String
    let tint: Color
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
    }
}
