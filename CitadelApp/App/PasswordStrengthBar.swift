import SwiftUI
import CitadelCore

/// Colored strength indicator bar for passwords.
struct PasswordStrengthBar: View {
    let password: String

    private var strength: PasswordStrength {
        PasswordStrength.evaluate(password)
    }

    private var color: Color {
        switch strength {
        case .empty: return .gray
        case .weak: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .strong: return .green
        case .excellent: return .blue
        }
    }

    private var fraction: Double {
        switch strength {
        case .empty: return 0
        case .weak: return 0.2
        case .fair: return 0.4
        case .good: return 0.6
        case .strong: return 0.8
        case .excellent: return 1.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeInOut(duration: 0.2), value: strength)
                }
            }
            .frame(height: 4)

            if strength != .empty {
                Text(strength.label)
                    .font(.caption2)
                    .foregroundStyle(color)
            }
        }
    }
}
