import SwiftUI

struct CardGroupBoxStyle: GroupBoxStyle {
    var spacing: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

extension GroupBoxStyle where Self == CardGroupBoxStyle {
    static var card: CardGroupBoxStyle { CardGroupBoxStyle() }
}
