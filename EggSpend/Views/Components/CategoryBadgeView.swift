import SwiftUI

struct CategoryBadgeView: View {
    let category: TransactionCategory
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(compact ? .caption : .subheadline)
            if !compact {
                Text(category.name)
                    .font(.subheadline)
            }
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, compact ? Space.sm : Space.md)
        .padding(.vertical, Space.xs)
        .background(category.color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name)
    }
}

#Preview {
    VStack(spacing: 12) {
        CategoryBadgeView(
            category: TransactionCategory(name: "Food & Dining", icon: "fork.knife", colorHex: "E67E22")
        )
        CategoryBadgeView(
            category: TransactionCategory(name: "Salary", icon: "briefcase.fill", colorHex: "27AE60"),
            compact: true
        )
    }
    .padding()
}
