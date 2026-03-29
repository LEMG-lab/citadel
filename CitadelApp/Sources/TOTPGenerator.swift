import Foundation
import CryptoKit

/// Parses otpauth:// URIs and generates TOTP codes per RFC 6238.
public struct TOTPGenerator: Sendable {

    public let secret: Data
    public let period: Int
    public let digits: Int
    public let algorithm: Algorithm

    public enum Algorithm: String {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    /// Parse an otpauth:// URI.
    /// Example: otpauth://totp/Label?secret=BASE32SECRET&period=30&digits=6&algorithm=SHA1
    public init?(uri: String) {
        guard uri.hasPrefix("otpauth://totp/") else { return nil }
        guard let url = URLComponents(string: uri) else { return nil }

        var secretStr: String?
        var period = 30
        var digits = 6
        var algorithm = Algorithm.sha1

        for item in url.queryItems ?? [] {
            switch item.name.lowercased() {
            case "secret":
                secretStr = item.value
            case "period":
                if let v = item.value.flatMap({ Int($0) }), v > 0 { period = v }
            case "digits":
                if let v = item.value.flatMap({ Int($0) }), v >= 4 && v <= 8 { digits = v }
            case "algorithm":
                if let v = item.value.flatMap({ Algorithm(rawValue: $0.uppercased()) }) {
                    algorithm = v
                }
            default:
                break
            }
        }

        guard let b32 = secretStr, let decoded = Self.base32Decode(b32) else { return nil }

        self.secret = decoded
        self.period = period
        self.digits = digits
        self.algorithm = algorithm
    }

    /// Generate TOTP code for a given timestamp.
    public func code(at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(period)
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: 8)

        let hash: Data
        switch algorithm {
        case .sha1:
            let key = SymmetricKey(data: secret)
            let auth = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key)
            hash = Data(auth)
        case .sha256:
            let key = SymmetricKey(data: secret)
            let auth = HMAC<SHA256>.authenticationCode(for: message, using: key)
            hash = Data(auth)
        case .sha512:
            let key = SymmetricKey(data: secret)
            let auth = HMAC<SHA512>.authenticationCode(for: message, using: key)
            hash = Data(auth)
        }

        // Dynamic truncation (RFC 4226 Section 5.4)
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let truncated = (UInt32(hash[offset]) & 0x7F) << 24
            | UInt32(hash[offset + 1]) << 16
            | UInt32(hash[offset + 2]) << 8
            | UInt32(hash[offset + 3])

        let modulus = UInt32(pow(10.0, Double(digits)))
        let otp = truncated % modulus

        return String(format: "%0\(digits)d", otp)
    }

    /// Seconds remaining until current code expires.
    public func secondsRemaining(at date: Date = Date()) -> Int {
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    // MARK: - Base32

    private static let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    static func base32Decode(_ input: String) -> Data? {
        let clean = input.uppercased().filter { $0 != "=" && $0 != " " }
        guard !clean.isEmpty else { return nil }

        let table: [Character: UInt8] = Dictionary(
            uniqueKeysWithValues: base32Alphabet.enumerated().map {
                (base32Alphabet[base32Alphabet.index(base32Alphabet.startIndex, offsetBy: $0.offset)], UInt8($0.offset))
            }
        )

        var bits = 0
        var accumulator: UInt32 = 0
        var output = Data()

        for char in clean {
            guard let value = table[char] else { return nil }
            accumulator = (accumulator << 5) | UInt32(value)
            bits += 5

            if bits >= 8 {
                bits -= 8
                output.append(UInt8((accumulator >> bits) & 0xFF))
            }
        }

        return output
    }
}
