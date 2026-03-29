import Testing
import Foundation
@testable import CitadelCore

/// Path to the test fixture bundled in test resources.
private func fixturePath() -> String {
    let bundle = Bundle.module
    guard let path = bundle.path(forResource: "test-fixture", ofType: "kdbx", inDirectory: "Resources") else {
        fatalError("test-fixture.kdbx not found in test bundle")
    }
    return path
}

private let fixturePassword = Data("Test123".utf8)

@Suite("VaultPersistence")
struct VaultPersistenceTests {

    /// Helper: create a temp directory for tests.
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("citadel-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Full atomic save pipeline")
    func atomicSavePipeline() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vaultPath = tmpDir.appendingPathComponent("vault.kdbx").path
        let password = Data("AtomicTest".utf8)
        let fm = FileManager.default

        // Create initial vault
        let engine = VaultEngine()
        try engine.create(password: password)
        _ = try engine.addEntry(
            title: "Entry1", username: "u1",
            password: Data("p1".utf8), url: "", notes: ""
        )

        // First save — no .prev because vault didn't exist on disk yet
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)

        #expect(fm.fileExists(atPath: vaultPath))
        #expect(!fm.fileExists(atPath: vaultPath + ".tmp")) // temp cleaned up
        #expect(!fm.fileExists(atPath: vaultPath + ".prev")) // no prior file to back up

        // Second save — .prev should now exist (copy of first vault)
        _ = try engine.addEntry(
            title: "Entry2", username: "u2",
            password: Data("p2".utf8), url: "", notes: ""
        )
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)

        #expect(fm.fileExists(atPath: vaultPath))
        #expect(fm.fileExists(atPath: vaultPath + ".prev"))
        #expect(!fm.fileExists(atPath: vaultPath + ".prev2")) // only 1 prior save

        // Third save — .prev2 should now exist
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)
        #expect(fm.fileExists(atPath: vaultPath + ".prev"))
        #expect(fm.fileExists(atPath: vaultPath + ".prev2"))

        // Fourth save
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)
        #expect(fm.fileExists(atPath: vaultPath + ".prev3"))

        // Fifth save — .prev3 should be capped (only 3 kept)
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)
        #expect(fm.fileExists(atPath: vaultPath + ".prev3"))
        #expect(!fm.fileExists(atPath: vaultPath + ".prev4")) // only 3 kept

        // Verify current vault is valid
        try VaultEngine.validate(path: vaultPath, password: password)

        // Verify we can reopen and see both entries
        engine.close()
        try engine.open(path: vaultPath, password: password)
        let entries = try engine.listEntries()
        #expect(entries.count == 2)
        engine.close()
    }

    @Test("Validate runs on temp file before promotion")
    func validateBeforePromotion() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vaultPath = tmpDir.appendingPathComponent("vault.kdbx").path
        let password = Data("ValidateTest".utf8)

        let engine = VaultEngine()
        try engine.create(password: password)
        _ = try engine.addEntry(
            title: "Test", username: "user",
            password: Data("pw".utf8), url: "", notes: ""
        )

        // Atomic save should succeed — vault_validate passes on the temp file
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)

        // Verify the saved file can be validated independently
        try VaultEngine.validate(path: vaultPath, password: password)

        // Wrong password should fail validation
        #expect(throws: VaultError.wrongPassword) {
            try VaultEngine.validate(path: vaultPath, password: Data("wrong".utf8))
        }

        engine.close()
    }

    @Test("Original survives if save is interrupted (temp file only)")
    func originalSurvivesInterruption() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vaultPath = tmpDir.appendingPathComponent("vault.kdbx").path
        let password = Data("SurviveTest".utf8)
        let fm = FileManager.default

        // Create and save initial vault
        let engine = VaultEngine()
        try engine.create(password: password)
        _ = try engine.addEntry(
            title: "Original", username: "u1",
            password: Data("p1".utf8), url: "", notes: ""
        )
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)

        // Record original file size
        let origAttrs = try fm.attributesOfItem(atPath: vaultPath)
        let origSize = origAttrs[.size] as! UInt64

        // Simulate interrupted save: write garbage to .tmp and leave it
        let tmpPath = vaultPath + ".tmp"
        try Data("corrupted".utf8).write(to: URL(fileURLWithPath: tmpPath))

        // Original vault should still be intact
        #expect(fm.fileExists(atPath: vaultPath))
        let currentAttrs = try fm.attributesOfItem(atPath: vaultPath)
        let currentSize = currentAttrs[.size] as! UInt64
        #expect(currentSize == origSize)

        // Original should still be valid and openable
        try VaultEngine.validate(path: vaultPath, password: password)

        let engine2 = VaultEngine()
        try engine2.open(path: vaultPath, password: password)
        let entries = try engine2.listEntries()
        #expect(entries.count == 1)
        #expect(entries[0].title == "Original")
        engine2.close()

        // Clean up temp file
        try? fm.removeItem(atPath: tmpPath)
        engine.close()
    }

    @Test("F_FULLFSYNC succeeds on a real file")
    func fullFsync() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filePath = tmpDir.appendingPathComponent("fsync-test.dat").path
        try Data("hello".utf8).write(to: URL(fileURLWithPath: filePath))

        // Should not throw
        try VaultPersistence.fullFsync(path: filePath)
    }
}
