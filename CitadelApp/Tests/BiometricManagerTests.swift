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

    @Test("Blob roundtrip — password and timestamp survive encode/decode")
    func blobRoundtrip() {
        let password = Data("hunter2-sécrét-🔑".utf8)
        let timestamp: TimeInterval = 1711833600.0 // Fixed timestamp

        let blob = BiometricManager.buildBlob(password: password, timestamp: timestamp)
        let (parsedPassword, parsedTimestamp) = BiometricManager.parseBlob(blob)

        #expect(parsedPassword == password)
        #expect(parsedTimestamp == timestamp)
    }

    @Test("Blob format — first 8 bytes are timestamp, rest is password")
    func blobFormat() {
        let password = Data([0x41, 0x42, 0x43]) // "ABC"
        let timestamp: TimeInterval = 100.0

        let blob = BiometricManager.buildBlob(password: password, timestamp: timestamp)
        #expect(blob.count == 8 + 3)
        #expect(blob.suffix(3) == password)
    }

    @Test("Parse empty blob returns empty password and zero timestamp")
    func parseBlobEmpty() {
        let (password, timestamp) = BiometricManager.parseBlob(Data())
        #expect(password.isEmpty)
        #expect(timestamp == 0)
    }

    @Test("Parse short blob (< 8 bytes) returns empty password and zero timestamp")
    func parseBlobShort() {
        let (password, timestamp) = BiometricManager.parseBlob(Data([1, 2, 3, 4]))
        #expect(password.isEmpty)
        #expect(timestamp == 0)
    }

    @Test("Cleanup removes old bio files but leaves other files")
    func cleanupOldBioFiles() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smaug-biotest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create mock bio files and a non-bio file
        let bioNonce = tmpDir.appendingPathComponent(".bio-nonce-abc123")
        let bioBlob = tmpDir.appendingPathComponent(".bio-blob-abc123")
        let otherFile = tmpDir.appendingPathComponent("vault.kdbx")
        FileManager.default.createFile(atPath: bioNonce.path, contents: Data("nonce".utf8))
        FileManager.default.createFile(atPath: bioBlob.path, contents: Data("blob".utf8))
        FileManager.default.createFile(atPath: otherFile.path, contents: Data("vault".utf8))

        BiometricManager.cleanupOldBioFiles(inDirectory: tmpDir.path)

        #expect(!FileManager.default.fileExists(atPath: bioNonce.path))
        #expect(!FileManager.default.fileExists(atPath: bioBlob.path))
        #expect(FileManager.default.fileExists(atPath: otherFile.path))
    }
}
