import SwiftUI

/// Gold shield icon for Smaug — clean and premium.
struct DragonIcon: View {
    var size: CGFloat = 64

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.90, green: 0.72, blue: 0.18),
                     Color(red: 0.75, green: 0.52, blue: 0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Image(systemName: "lock.shield.fill")
            .font(.system(size: size * 0.75, weight: .light))
            .foregroundStyle(goldGradient)
            .frame(width: size, height: size)
    }
}
