import SwiftUI

struct NestBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.nestCream,
                Color.nestLeafGreen.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Nest Background") {
    ZStack {
        NestBackground()
        Text("EggSpend")
            .font(.title.bold())
            .foregroundStyle(Color.nestBrown)
    }
}
