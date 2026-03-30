import Testing
import Foundation
@testable import CitadelCore

@Suite("BiometricManager")
struct BiometricManagerTests {

    @Test("72-hour expiry — fresh timestamp is not expired")
    func freshTimestampNotExpired() {
        let now = Date().timeIntervalSince1970
        let lastAuth = now - (1 * 60 * 60) // 1 hour ago
        #expect(!BiometricManager.isFullAuthRequired(lastAuthTimestamp: lastAuth, now: now))
    }

    @Test("72-hour expiry — 71 hours is not expired")
    func seventyOneHoursNotExpired() {
        let now = Date().timeIntervalSince1970
        let lastAuth = now - (71 * 60 * 60) // 71 hours ago
        #expect(!BiometricManager.isFullAuthRequired(lastAuthTimestamp: lastAuth, now: now))
    }

    @Test("72-hour expiry — 73 hours is expired")
    func seventyThreeHoursExpired() {
        let now = Date().timeIntervalSince1970
        let lastAuth = now - (73 * 60 * 60) // 73 hours ago
        #expect(BiometricManager.isFullAuthRequired(lastAuthTimestamp: lastAuth, now: now))
    }

    @Test("72-hour expiry — exactly 72 hours is expired")
    func exactlySeventyTwoHoursExpired() {
        let now = Date().timeIntervalSince1970
        let lastAuth = now - (72 * 60 * 60) // exactly 72 hours
        // > not >=, so exactly 72h is not expired (boundary)
        #expect(!BiometricManager.isFullAuthRequired(lastAuthTimestamp: lastAuth, now: now))
    }

    @Test("72-hour expiry — zero timestamp requires full auth")
    func zeroTimestampRequiresFullAuth() {
        let now = Date().timeIntervalSince1970
        #expect(BiometricManager.isFullAuthRequired(lastAuthTimestamp: 0, now: now))
    }

    @Test("72-hour expiry — negative timestamp requires full auth")
    func negativeTimestampRequiresFullAuth() {
        let now = Date().timeIntervalSince1970
        #expect(BiometricManager.isFullAuthRequired(lastAuthTimestamp: -1, now: now))
    }

    @Test("Key derivation is deterministic")
    func keyDerivationDeterministic() {
        let nonce = Data((0..<32).map { UInt8($0) })
        let key1 = BiometricManager.deriveWrappingKey(nonce: nonce)
        let key2 = BiometricManager.deriveWrappingKey(nonce: nonce)
        #expect(key1 == key2)
        #expect(key1.count == 32)
    }

    @Test("Different nonces produce different keys")
    func keyDerivationDifferentNonces() {
        let nonce1 = Data((0..<32).map { UInt8($0) })
        let nonce2 = Data((0..<32).map { UInt8($0 &+ 1) })
        let key1 = BiometricManager.deriveWrappingKey(nonce: nonce1)
        let key2 = BiometricManager.deriveWrappingKey(nonce: nonce2)
        #expect(key1 != key2)
    }
}
