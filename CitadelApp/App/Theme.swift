import SwiftUI

// MARK: - Color Palette

extension Color {
    static let citadelAccent = Color(red: 0.231, green: 0.510, blue: 0.965)   // #3B82F6
    static let citadelDanger = Color(red: 0.937, green: 0.267, blue: 0.267)   // #EF4444
    static let citadelSuccess = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let citadelWarning = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B
    static let citadelSecondary = Color(red: 0.545, green: 0.584, blue: 0.647) // #8B95A5

    static let cardBackground = Color(.windowBackgroundColor).opacity(0.5)
    static let fieldBackground = Color(.controlBackgroundColor)
}

// MARK: - Reusable Components

/// Colored circle behind an SF Symbol — used for entry type icons and settings rows.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// Uppercase section header matching the design spec.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.citadelSecondary)
    }
}

/// A single labeled field row used in the detail view.
struct FieldCard<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(Color.citadelSecondary)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Circular progress ring used for TOTP countdown and health score.
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

/// Pill-shaped metadata tag.
struct MetadataPill: View {
    let icon: String
    let text: String
    var color: Color = .citadelSecondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }
}

/// Count badge used in Password Health categories.
struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(count == 0 ? Color.gray : color, in: Capsule())
    }
}
