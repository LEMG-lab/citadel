import Foundation

/// Pre-defined field for a template.
public struct TemplateField {
    public let key: String
    public let placeholder: String
    public let isProtected: Bool

    public init(key: String, placeholder: String = "", isProtected: Bool = false) {
        self.key = key
        self.placeholder = placeholder
        self.isProtected = isProtected
    }
}

/// Entry templates that pre-populate custom fields for common credential types.
public enum EntryTemplate: String, CaseIterable, Identifiable {
    case login
    case cryptoWallet
    case serverSSH
    case apiKey
    case database
    case emailAccount
    case creditCard
    case identity
    case secureNote
    case recoveryCodes
    case softwareLicense

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .login:           return "Login"
        case .cryptoWallet:    return "Crypto Wallet"
        case .serverSSH:       return "Server / SSH"
        case .apiKey:          return "API Key"
        case .database:        return "Database"
        case .emailAccount:    return "Email Account"
        case .creditCard:      return "Credit Card"
        case .identity:        return "Identity"
        case .secureNote:      return "Secure Note"
        case .recoveryCodes:   return "Recovery Codes"
        case .softwareLicense: return "Software License"
        }
    }

    public var icon: String {
        switch self {
        case .login:           return "key.fill"
        case .cryptoWallet:    return "bitcoinsign.circle"
        case .serverSSH:       return "server.rack"
        case .apiKey:          return "curlybraces"
        case .database:        return "cylinder"
        case .emailAccount:    return "envelope.fill"
        case .creditCard:      return "creditcard.fill"
        case .identity:        return "person.text.rectangle"
        case .secureNote:      return "note.text"
        case .recoveryCodes:   return "key.viewfinder"
        case .softwareLicense: return "purchased"
        }
    }

    /// Whether this template creates a "secure_note" entry type.
    public var isSecureNote: Bool {
        self == .secureNote
    }

    /// Whether the template uses the standard username/password/URL fields.
    public var usesStandardFields: Bool {
        switch self {
        case .secureNote, .identity, .creditCard:
            return false
        default:
            return true
        }
    }

    /// Custom fields to pre-populate.
    public var fields: [TemplateField] {
        switch self {
        case .login:
            return [] // Uses standard title/username/password/URL/notes

        case .cryptoWallet:
            return [
                TemplateField(key: "Wallet Name", placeholder: "e.g. MetaMask"),
                TemplateField(key: "Address", placeholder: "0x..."),
                TemplateField(key: "Seed Phrase", placeholder: "12 or 24 words", isProtected: true),
                TemplateField(key: "Private Key", placeholder: "", isProtected: true),
                TemplateField(key: "Network", placeholder: "Ethereum / Avalanche / Bitcoin / Solana"),
            ]

        case .serverSSH:
            return [
                TemplateField(key: "Hostname", placeholder: "example.com"),
                TemplateField(key: "IP Address", placeholder: "192.168.1.1"),
                TemplateField(key: "Port", placeholder: "22"),
                TemplateField(key: "SSH Key", placeholder: "Paste private key", isProtected: true),
                TemplateField(key: "Root Password", placeholder: "", isProtected: true),
                TemplateField(key: "Provider", placeholder: "AWS / DigitalOcean / Hetzner"),
            ]

        case .apiKey:
            return [
                TemplateField(key: "Service Name", placeholder: "e.g. OpenAI, Stripe"),
                TemplateField(key: "API Key", placeholder: "", isProtected: true),
                TemplateField(key: "API Secret", placeholder: "", isProtected: true),
                TemplateField(key: "Endpoint URL", placeholder: "https://api.example.com"),
                TemplateField(key: "Documentation URL", placeholder: "https://docs.example.com"),
            ]

        case .database:
            return [
                TemplateField(key: "Hostname", placeholder: "db.example.com"),
                TemplateField(key: "Port", placeholder: "5432"),
                TemplateField(key: "Database Name", placeholder: "mydb"),
                TemplateField(key: "Connection String", placeholder: "postgres://...", isProtected: true),
            ]

        case .emailAccount:
            return [
                TemplateField(key: "Email", placeholder: "user@example.com"),
                TemplateField(key: "IMAP Server", placeholder: "imap.example.com"),
                TemplateField(key: "SMTP Server", placeholder: "smtp.example.com"),
                TemplateField(key: "Port", placeholder: "993"),
                TemplateField(key: "App Password", placeholder: "", isProtected: true),
            ]

        case .creditCard:
            return [
                TemplateField(key: "Cardholder Name", placeholder: ""),
                TemplateField(key: "Card Number", placeholder: "", isProtected: true),
                TemplateField(key: "Expiry Date", placeholder: "MM/YY"),
                TemplateField(key: "CVV", placeholder: "", isProtected: true),
                TemplateField(key: "Billing Address", placeholder: ""),
                TemplateField(key: "PIN", placeholder: "", isProtected: true),
            ]

        case .identity:
            return [
                TemplateField(key: "Full Name", placeholder: ""),
                TemplateField(key: "Date of Birth", placeholder: "YYYY-MM-DD"),
                TemplateField(key: "ID Type", placeholder: "Passport / Driver License / National ID"),
                TemplateField(key: "ID Number", placeholder: "", isProtected: true),
                TemplateField(key: "Issuing Country", placeholder: ""),
                TemplateField(key: "Expiry Date", placeholder: "YYYY-MM-DD"),
                TemplateField(key: "Address", placeholder: ""),
                TemplateField(key: "Phone", placeholder: ""),
            ]

        case .secureNote:
            return [] // Just title + notes

        case .recoveryCodes:
            return [
                TemplateField(key: "Service Name", placeholder: "e.g. GitHub, Google"),
                TemplateField(key: "Recovery Codes", placeholder: "One per line", isProtected: true),
            ]

        case .softwareLicense:
            return [
                TemplateField(key: "Product Name", placeholder: ""),
                TemplateField(key: "License Key", placeholder: "", isProtected: true),
                TemplateField(key: "Email", placeholder: ""),
                TemplateField(key: "Purchase Date", placeholder: "YYYY-MM-DD"),
                TemplateField(key: "Expiry", placeholder: "Perpetual / YYYY-MM-DD"),
            ]
        }
    }
}
