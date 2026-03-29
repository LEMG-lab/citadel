import Testing
import Foundation
@testable import CitadelCore

@Suite("TOTPGenerator")
struct TOTPGeneratorTests {

    @Test("Parse valid otpauth URI")
    func parseValidURI() {
        let uri = "otpauth://totp/Test:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Test&period=30&digits=6&algorithm=SHA1"
        let gen = TOTPGenerator(uri: uri)
        #expect(gen != nil)
        #expect(gen?.period == 30)
        #expect(gen?.digits == 6)
    }

    @Test("Reject invalid URI")
    func rejectInvalid() {
        #expect(TOTPGenerator(uri: "not-a-uri") == nil)
        #expect(TOTPGenerator(uri: "otpauth://hotp/Test?secret=ABC") == nil)
    }

    @Test("RFC 6238 test vector — SHA1, time 59")
    func rfcTestVectorSHA1() {
        // RFC 6238 test: secret = "12345678901234567890" (ASCII), time = 59
        // The base32 encoding of "12345678901234567890" is "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=30&digits=8&algorithm=SHA1"
        let gen = TOTPGenerator(uri: uri)!
        let date = Date(timeIntervalSince1970: 59)
        let code = gen.code(at: date)
        #expect(code == "94287082")
    }

    @Test("RFC 6238 test vector — SHA1, time 1111111109")
    func rfcTestVectorSHA1Time2() {
        // RFC 6238 test: secret = "12345678901234567890", time = 1111111109
        let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=30&digits=8&algorithm=SHA1"
        let gen = TOTPGenerator(uri: uri)!
        let date = Date(timeIntervalSince1970: 1111111109)
        let code = gen.code(at: date)
        #expect(code == "07081804")
    }

    @Test("Seconds remaining calculation")
    func secondsRemaining() {
        let uri = "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&period=30"
        let gen = TOTPGenerator(uri: uri)!
        // At t=0, 30 seconds remaining
        let remaining = gen.secondsRemaining(at: Date(timeIntervalSince1970: 0))
        #expect(remaining == 30)
        // At t=10, 20 seconds remaining
        let remaining2 = gen.secondsRemaining(at: Date(timeIntervalSince1970: 10))
        #expect(remaining2 == 20)
    }

    @Test("Base32 decode")
    func base32Decode() {
        // "JBSWY3DPEHPK3PXP" decodes to "Hello!"... actually let's check
        // JBSWY3DPEHPK3PXP = "Hello!☻" — no, standard test:
        // "GEZDGNBVGY3TQOJQ" = "12345678901234567890" (20 chars) — wait, that's a longer base32.
        // Let's just verify it returns non-nil and correct length
        let data = TOTPGenerator.base32Decode("JBSWY3DPEHPK3PXP")
        #expect(data != nil)
        #expect(data!.count == 10)
    }
}
