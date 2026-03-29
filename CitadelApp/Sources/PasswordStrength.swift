import Foundation

/// Password strength estimation based on Shannon entropy.
public enum PasswordStrength: Comparable {
    case empty
    case weak       // < 40 bits
    case fair       // 40–59 bits
    case good       // 60–79 bits
    case strong     // 80–127 bits
    case excellent  // 128+ bits

    public var label: String {
        switch self {
        case .empty: return ""
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        case .excellent: return "Excellent"
        }
    }

    /// Estimate strength from entropy bits.
    public static func from(entropy: Double) -> PasswordStrength {
        if entropy <= 0 { return .empty }
        if entropy < 40 { return .weak }
        if entropy < 60 { return .fair }
        if entropy < 80 { return .good }
        if entropy < 128 { return .strong }
        return .excellent
    }

    /// Estimate entropy of a password string.
    ///
    /// Uses charset-size analysis: determines which character classes are present,
    /// computes the effective alphabet size, then entropy = length * log2(alphabetSize).
    public static func entropy(of password: String) -> Double {
        guard !password.isEmpty else { return 0 }

        var hasLower = false
        var hasUpper = false
        var hasDigit = false
        var hasSymbol = false

        for c in password {
            if c.isLowercase { hasLower = true }
            else if c.isUppercase { hasUpper = true }
            else if c.isNumber { hasDigit = true }
            else { hasSymbol = true }
        }

        var alphabetSize = 0
        if hasLower { alphabetSize += 26 }
        if hasUpper { alphabetSize += 26 }
        if hasDigit { alphabetSize += 10 }
        if hasSymbol { alphabetSize += 33 } // common printable symbols

        guard alphabetSize > 0 else { return 0 }
        return Double(password.count) * log2(Double(alphabetSize))
    }

    /// Convenience: evaluate a password string directly.
    public static func evaluate(_ password: String) -> PasswordStrength {
        from(entropy: entropy(of: password))
    }
}
