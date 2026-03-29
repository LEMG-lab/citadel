import Testing
import Foundation
@testable import CitadelCore

/// Path to the test fixture bundled in test resources.
private func fixturePath() -> String {
    // When running via `swift test`, Bundle.module gives us the resource bundle.
    let bundle = Bundle.module
    guard let path = bundle.path(forResource: "test-fixture", ofType: "kdbx", inDirectory: "Resources") else {
        fatalError("test-fixture.kdbx not found in test bundle")
    }
    return path
}

private let fixturePassword = Data("Test123".utf8)

@Suite("VaultEngine")
struct VaultEngineTests {

    @Test("Open fixture and list entries")
    func openAndList() throws {
        let engine = VaultEngine()
        try engine.open(path: fixturePath(), password: fixturePassword)
        defer { engine.close() }

        let entries = try engine.listEntries()
        #expect(entries.count == 3)

        let titles = entries.map(\.title)
        #expect(titles.contains("Pruenba1 "))
        #expect(titles.contains("Fake test 2"))
        #expect(titles.contains("prueba3"))
    }

    @Test("Get entry returns correct fields")
    func getEntry() throws {
        let engine = VaultEngine()
        try engine.open(path: fixturePath(), password: fixturePassword)
        defer { engine.close() }

        let entries = try engine.listEntries()
        guard let prueba = entries.first(where: { $0.title == "Fake test 2" }) else {
            Issue.record("Fake test 2 not found")
            return
        }

        let detail = try engine.getEntry(uuid: prueba.id)
        #expect(detail.title == "Fake test 2")
        #expect(detail.username == "prueba@gmail.com")
        #expect(detail.password == Data("Test123".utf8))
        #expect(detail.url == "http://gmail.com")
        #expect(detail.notes == "")
    }

    @Test("Add entry, save, reopen, verify")
    func addEntrySaveReopen() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vaultPath = tmpDir.appendingPathComponent("test.kdbx").path
        let password = Data("TestPw123".utf8)

        // Create, add entry, save
        let engine = VaultEngine()
        try engine.create(password: password)
        let uuid = try engine.addEntry(
            title: "GitHub",
            username: "alice",
            password: Data("s3cret".utf8),
            url: "https://github.com",
            notes: "dev"
        )
        try engine.saveTo(path: vaultPath)
        engine.close()

        // Reopen and verify
        try engine.open(path: vaultPath, password: password)
        defer { engine.close() }

        let entries = try engine.listEntries()
        #expect(entries.count == 1)
        #expect(entries[0].title == "GitHub")

        let detail = try engine.getEntry(uuid: uuid)
        #expect(detail.username == "alice")
        #expect(detail.password == Data("s3cret".utf8))
        #expect(detail.url == "https://github.com")
        #expect(detail.notes == "dev")
    }

    @Test("Wrong password throws wrongPassword")
    func wrongPassword() throws {
        let engine = VaultEngine()
        #expect(throws: VaultError.wrongPassword) {
            try engine.open(path: fixturePath(), password: Data("wrong".utf8))
        }
    }

    @Test("Empty password throws emptyPassword on create")
    func emptyPasswordCreate() throws {
        let engine = VaultEngine()
        #expect(throws: VaultError.emptyPassword) {
            try engine.create(password: Data())
        }
    }

    @Test("Close sets isOpen to false")
    func closeState() throws {
        let engine = VaultEngine()
        try engine.open(path: fixturePath(), password: fixturePassword)
        #expect(engine.isOpen)
        engine.close()
        #expect(!engine.isOpen)
    }

    @Test("Password generation returns requested length")
    func generatePassword() throws {
        let pw = try VaultEngine.generatePassword(length: 32, charset: 0xF) // all charsets
        #expect(pw.count == 32)
    }
}
