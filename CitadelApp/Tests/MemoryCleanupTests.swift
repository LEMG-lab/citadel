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

@Suite("Memory & Persistence Cleanup")
struct MemoryCleanupTests {

    @Test("Engine close clears internal handle")
    func engineCloseState() throws {
        let engine = VaultEngine()
        try engine.open(path: fixturePath(), password: fixturePassword)
        #expect(engine.isOpen, "Engine should be open after open()")

        // Read some data to ensure entries are loaded
        let entries = try engine.listEntries()
        #expect(entries.count == 3)

        let detail = try engine.getEntry(uuid: entries[0].id)
        #expect(!detail.password.isEmpty, "Should have read a password")

        // Close the engine (simulates lockVault's engine.close())
        engine.close()

        // Verify internal state is cleared
        #expect(!engine.isOpen, "Engine should not be open after close()")

        // Operations should fail after close
        #expect(throws: VaultError.self) {
            _ = try engine.listEntries()
        }
        #expect(throws: VaultError.self) {
            _ = try engine.getEntry(uuid: entries[0].id)
        }
    }

    @Test("Double close is safe")
    func doubleClose() throws {
        let engine = VaultEngine()
        try engine.open(path: fixturePath(), password: fixturePassword)
        engine.close()
        // Second close should not crash or throw
        engine.close()
        #expect(!engine.isOpen)
    }

    @Test("Data.resetBytes zeroes password memory")
    func dataResetBytesZeroesMemory() throws {
        // Simulate the AppState.lockVault() password zeroing pattern
        var password: Data? = Data("SuperSecretPassword123!".utf8)

        // Verify it has content
        #expect(password!.count > 0)
        #expect(password != Data(repeating: 0, count: password!.count))

        // Zero the bytes (mirrors AppState.lockVault's zeroing logic)
        if password != nil {
            password!.resetBytes(in: 0..<password!.count)
        }

        // Verify the data is now all zeroes
        let allZero = password!.allSatisfy { $0 == 0 }
        #expect(allZero, "Password bytes should be zeroed after resetBytes")

        // Then nil it out
        password = nil
        #expect(password == nil)
    }

    @Test("Lock flow: open, read, close clears all observable state")
    func lockFlowSimulation() throws {
        // Simulate AppState's full lock flow at the engine level
        let engine = VaultEngine()
        var entries: [VaultEntrySummary] = []
        var currentPassword: Data? = fixturePassword
        var selectedEntryID: String?

        // Unlock
        try engine.open(path: fixturePath(), password: currentPassword!)
        entries = try engine.listEntries()
        selectedEntryID = entries.first?.id
        #expect(entries.count == 3)
        #expect(selectedEntryID != nil)
        #expect(currentPassword != nil)

        // Lock (mirrors AppState.lockVault exactly)
        engine.close()
        if currentPassword != nil {
            currentPassword!.resetBytes(in: 0..<currentPassword!.count)
        }
        currentPassword = nil
        entries = []
        selectedEntryID = nil

        // Verify ALL state is cleared
        #expect(!engine.isOpen, "Engine handle should be nil")
        #expect(entries.isEmpty, "Entries array should be empty")
        #expect(selectedEntryID == nil, "Selected entry should be nil")
        #expect(currentPassword == nil, "Current password should be nil")
    }

    @Test("Entry detail password data is independent copy")
    func entryPasswordIsIndependentCopy() throws {
        let engine = VaultEngine()
        try engine.open(path: fixturePath(), password: fixturePassword)
        defer { engine.close() }

        let entries = try engine.listEntries()
        let detail = try engine.getEntry(uuid: entries[0].id)
        var passwordCopy = detail.password

        // Mutating our copy should not affect what the engine returns
        passwordCopy.resetBytes(in: 0..<passwordCopy.count)
        let allZero = passwordCopy.allSatisfy { $0 == 0 }
        #expect(allZero, "Our copy should be zeroed")

        // Re-fetch: engine should still return the original
        let detail2 = try engine.getEntry(uuid: entries[0].id)
        #expect(!detail2.password.isEmpty, "Engine should still have the password")
        #expect(detail2.password != passwordCopy, "Fresh fetch should differ from zeroed copy")
    }

    @Test("Null bytes in strings are rejected before FFI")
    func nullByteRejection() throws {
        let engine = VaultEngine()
        try engine.create(password: Data("test123".utf8))
        defer { engine.close() }

        // Title with embedded null byte
        #expect(throws: VaultError.self) {
            _ = try engine.addEntry(
                title: "before\0after", username: "u",
                password: Data("pw".utf8), url: "", notes: ""
            )
        }

        // Username with embedded null byte
        #expect(throws: VaultError.self) {
            _ = try engine.addEntry(
                title: "ok", username: "user\0name",
                password: Data("pw".utf8), url: "", notes: ""
            )
        }

        // URL with embedded null byte
        #expect(throws: VaultError.self) {
            _ = try engine.addEntry(
                title: "ok", username: "u",
                password: Data("pw".utf8), url: "https://\0evil.com", notes: ""
            )
        }

        // Notes with embedded null byte
        #expect(throws: VaultError.self) {
            _ = try engine.addEntry(
                title: "ok", username: "u",
                password: Data("pw".utf8), url: "", notes: "line1\0line2"
            )
        }

        // Clean strings should still work
        let uuid = try engine.addEntry(
            title: "Normal", username: "user",
            password: Data("pw".utf8), url: "https://ok.com", notes: "fine"
        )
        let detail = try engine.getEntry(uuid: uuid)
        #expect(detail.title == "Normal")
    }
}
