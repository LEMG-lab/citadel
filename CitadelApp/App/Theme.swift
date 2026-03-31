import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private static let defaultsKey = "smaug.appearanceMode"

    static var saved: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? "system"
        return AppearanceMode(rawValue: raw) ?? .system
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: AppearanceMode.defaultsKey)
    }
}

// MARK: - Adaptive Color Palette

extension Color {
    static let citadelAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(red: 0.039, green: 0.518, blue: 1.0, alpha: 1.0)   // #0A84FF
            : NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)     // #007AFF
    })
    static let citadelDanger = Color(red: 0.937, green: 0.267, blue: 0.267)   // #EF4444
    static let citadelSuccess = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let citadelWarning = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B
    static let citadelSecondary = Color(.secondaryLabelColor)
    static let citadelTertiary = Color(.tertiaryLabelColor)

    static let sidebarBackground = Color(.controlBackgroundColor)
    static let contentBackground = Color(.windowBackgroundColor)
    static let cardBackground = Color(.controlBackgroundColor)
    static let fieldBackground = Color(.textBackgroundColor)
    static let subtleSeparator = Color(.separatorColor)
}

// MARK: - Accent Color (Light/Dark adaptive)

extension ShapeStyle where Self == Color {
    static var accentBlue: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.039, green: 0.518, blue: 1.0, alpha: 1.0)   // #0A84FF
                : NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)     // #007AFF
        })
    }
}

// MARK: - Reusable Components

/// Colored circle behind an SF Symbol.
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

/// Section header with uppercase label.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.citadelSecondary)
    }
}

/// A labeled field row for the detail view.
struct FieldCard<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(Color.citadelSecondary)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
    }
}

/// Circular progress ring.
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

/// Count badge.
struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(count == 0 ? Color.gray.opacity(0.5) : color, in: Capsule())
    }
}

/// Entry icon — colored circle with first letter or SF Symbol.
struct EntryIcon: View {
    let title: String
    let entryType: String
    var size: CGFloat = 34

    private var letter: String {
        let first = title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return first.isEmpty ? "?" : first
    }

    private var iconColor: Color {
        if entryType == "secure_note" { return .purple }
        let colors: [Color] = [.blue, .green, .orange, .pink, .teal, .indigo, .cyan, .mint]
        let hash = abs(title.hashValue)
        return colors[hash % colors.count]
    }

    private var cryptoIcon: String? {
        switch entryType {
        case "seed_phrase":        return "rectangle.grid.2x2"
        case "private_key":        return "lock.fill"
        case "multi_chain_wallet": return "link.circle"
        case "crypto_wallet":      return "bitcoinsign.circle"
        default:                   return nil
        }
    }

    var body: some View {
        if entryType == "secure_note" {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: size, height: size)
                Image(systemName: "note.text")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else if let symbol = cryptoIcon {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.orange.gradient)
                    .frame(width: size, height: size)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: size, height: size)
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

