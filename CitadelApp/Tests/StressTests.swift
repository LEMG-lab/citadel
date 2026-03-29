import Testing
import Foundation
@testable import CitadelCore

private func fixturePath() -> String {
    let bundle = Bundle.module
    guard let path = bundle.path(forResource: "test-fixture", ofType: "kdbx", inDirectory: "Resources") else {
        fatalError("test-fixture.kdbx not found in test bundle")
    }
    return path
}

private let fixturePassword = Data("Test123".utf8)

/// Run a subprocess and return stdout. Throws on non-zero exit.
private func runProcess(_ executable: String, _ args: String...) throws -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        throw NSError(domain: "Process", code: Int(proc.terminationStatus))
    }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

/// If keepassxc-cli is installed, verify the vault can be opened. Silently skips otherwise.
private func verifyWithKeePassXC(path: String, password: String) {
    let candidates = [
        "/opt/homebrew/bin/keepassxc-cli",
        "/usr/local/bin/keepassxc-cli",
        "/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli",
    ]
    guard let cli = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
        return
    }
    do {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = ["ls", "-q", path]
        let stdin = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        stdin.fileHandleForWriting.write(Data((password + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0, "KeePassXC rejected vault at \(path)")
    } catch {
        // Skip silently if cli fails to run
    }
}

@Suite("Stress Tests")
struct StressTests {

    private let fm = FileManager.default

    private func makeTmpDir() -> URL {
        let url = fm.temporaryDirectory
            .appendingPathComponent("citadel-stress-\(UUID().uuidString)")
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // =========================================================================
    // MARK: - 1. Bulk Test: 200 Varied Entries
    // =========================================================================

    @Test("1. Bulk: 200 varied entries survive save/close/reopen")
    func bulk200Entries() throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let path = dir.appendingPathComponent("bulk.kdbx").path
        let password = Data("BulkTestPass!123".utf8)

        let engine = VaultEngine()
        try engine.create(password: password)

        struct Expected {
            let title: String; let username: String; let password: Data
            let url: String; let notes: String
        }
        var expected: [String: Expected] = [:]

        for i in 0..<200 {
            let (t, u, p, r, n) = entryVariant(i)
            let uuid = try engine.addEntry(title: t, username: u, password: p, url: r, notes: n)
            expected[uuid] = Expected(title: t, username: u, password: p, url: r, notes: n)
        }

        try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: password)
        engine.close()

        // Reopen and verify every field
        let engine2 = VaultEngine()
        try engine2.open(path: path, password: password)
        defer { engine2.close() }

        let entries = try engine2.listEntries()
        #expect(entries.count == 200, "Expected 200, got \(entries.count)")

        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for (uuid, exp) in expected {
            guard let s = byID[uuid] else {
                Issue.record("Missing entry \(uuid) (\(exp.title))")
                continue
            }
            #expect(s.title == exp.title, "Title mismatch for \(uuid)")
            #expect(s.username == exp.username, "Username mismatch for \(uuid)")
            #expect(s.url == exp.url, "URL mismatch for \(uuid)")

            let d = try engine2.getEntry(uuid: uuid)
            #expect(d.password == exp.password, "Password mismatch for \(exp.title)")
            #expect(d.notes == exp.notes, "Notes mismatch for \(exp.title)")
        }

        try VaultEngine.validate(path: path, password: password)
        verifyWithKeePassXC(path: path, password: "BulkTestPass!123")
    }

    private func entryVariant(_ i: Int) -> (String, String, Data, String, String) {
        switch i % 10 {
        case 0: // Long title
            return (
                String(repeating: "LongTitle", count: 50) + "#\(i)",
                "user\(i)@test.com",
                Data("pass\(i)".utf8),
                "https://example.com/\(i)",
                "Normal note \(i)"
            )
        case 1: // Unicode (CJK, emoji)
            return (
                "日本語タイトル\(i)🔑",
                "用户\(i)@例え.jp",
                Data("パスワード\(i)".utf8),
                "https://例え.jp/\(i)",
                "Arabic: مرحبا Hebrew: שלום Korean: 한국어 \(i)"
            )
        case 2: // Special symbols in password
            return (
                "SpecialPw#\(i)",
                "special\(i)",
                Data("!@#$%^&*()_+-=[]{}|;':\",./<>?`~\(i)".utf8),
                "",
                ""
            )
        case 3: // Empty optional fields
            return (
                "EmptyFields#\(i)",
                "",
                Data("p\(i)".utf8),
                "",
                ""
            )
        case 4: // Very long notes (~5 KB)
            return (
                "LongNotes#\(i)",
                "user\(i)",
                Data("pass\(i)".utf8),
                "https://example.com",
                String(repeating: "This is a very long note with content. ", count: 200) + "#\(i)"
            )
        case 5: // URL with query strings
            return (
                "QueryURL#\(i)",
                "user\(i)",
                Data("pass\(i)".utf8),
                "https://example.com/path?key=value&id=\(i)&token=abc&redirect=https%3A%2F%2Fother.com",
                "Has complex URL"
            )
        case 6: // Emoji-heavy password
            return (
                "EmojiPw#\(i)",
                "emoji\(i)",
                Data("🔒🗝️💻🔐🛡️\(i)".utf8),
                "https://emoji.test",
                "Password has emoji"
            )
        case 7: // 500-char password
            return (
                "LongPw#\(i)",
                "longpw\(i)",
                Data((String(repeating: "Aa1!", count: 125) + "\(i)").utf8),
                "",
                ""
            )
        case 8: // CJK everywhere
            return (
                "中文标题\(i)",
                "用户名\(i)",
                Data("密码\(i)".utf8),
                "https://中文.com/\(i)",
                "笔记\(i) 日本語テスト 한국어테스트"
            )
        case 9: // Whitespace edge cases
            return (
                "  Spaces  #\(i)  ",
                "\t\tuser\(i)\t",
                Data("  spaces  \(i)  ".utf8),
                "  https://example.com  ",
                "\n\nNewlines\n\n\(i)\n\n"
            )
        default: fatalError()
        }
    }

    // =========================================================================
    // MARK: - 2. Crash Recovery
    // =========================================================================

    @Test("2. Crash recovery: corrupted .tmp leaves vault and .prev intact")
    func crashRecovery() throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let path = dir.appendingPathComponent("vault.kdbx").path
        let password = Data("CrashTest!99".utf8)

        let engine = VaultEngine()
        try engine.create(password: password)

        for i in 0..<50 {
            _ = try engine.addEntry(
                title: "Entry\(i)", username: "user\(i)",
                password: Data("pass\(i)".utf8),
                url: "https://\(i).example.com", notes: "Note \(i)"
            )
        }

        try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: password)

        // Snapshot state
        let vaultBytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let prevPath = path + ".prev"
        let prevExists = fm.fileExists(atPath: prevPath)
        let prevBytes = prevExists ? try Data(contentsOf: URL(fileURLWithPath: prevPath)) : nil

        // Simulate mid-save crash: write garbage .tmp
        let tmpPath = path + ".tmp"
        try Data("THIS IS CORRUPTED GARBAGE NOT A KDBX FILE \(UUID())".utf8)
            .write(to: URL(fileURLWithPath: tmpPath))

        // Vault untouched
        let afterBytes = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(vaultBytes == afterBytes, "Vault data changed after crash simulation")

        // .prev untouched
        if let prev = prevBytes {
            let afterPrev = try Data(contentsOf: URL(fileURLWithPath: prevPath))
            #expect(prev == afterPrev, ".prev changed after crash simulation")
        }

        // Vault still opens with all 50 entries
        engine.close()
        let engine2 = VaultEngine()
        try engine2.open(path: path, password: password)
        let entries = try engine2.listEntries()
        #expect(entries.count == 50, "Expected 50 entries after crash, got \(entries.count)")

        // .prev is also openable
        if prevExists {
            try VaultEngine.validate(path: prevPath, password: password)
        }

        // A real save after the crash succeeds and overwrites .tmp
        _ = try engine2.addEntry(
            title: "AfterCrash", username: "", password: Data("new".utf8), url: "", notes: ""
        )
        try VaultPersistence.atomicSave(engine: engine2, vaultPath: path, password: password)
        #expect(!fm.fileExists(atPath: tmpPath), ".tmp should be gone after successful save")
        engine2.close()

        // Final verification
        let engine3 = VaultEngine()
        try engine3.open(path: path, password: password)
        let final_ = try engine3.listEntries()
        #expect(final_.count == 51, "Expected 51 entries after recovery save, got \(final_.count)")
        engine3.close()
    }

    // =========================================================================
    // MARK: - 3. Password Edge Cases
    // =========================================================================

    /// Helper: create vault, add entry with given password, save, close, reopen, verify round-trip.
    private func verifyPasswordRoundTrip(_ entryPassword: Data, label: String) throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let path = dir.appendingPathComponent("pw-\(label).kdbx").path
        let vaultPw = Data("VaultPass123".utf8)

        let engine = VaultEngine()
        try engine.create(password: vaultPw)
        let uuid = try engine.addEntry(
            title: "PW Test \(label)", username: "user",
            password: entryPassword, url: "", notes: ""
        )
        try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: vaultPw)
        engine.close()

        let engine2 = VaultEngine()
        try engine2.open(path: path, password: vaultPw)
        defer { engine2.close() }
        let detail = try engine2.getEntry(uuid: uuid)
        #expect(
            detail.password == entryPassword,
            "Password round-trip failed for \(label): expected \(entryPassword.count) bytes, got \(detail.password.count)"
        )
    }

    @Test("3a. Password edge case: empty string")
    func passwordEmpty() throws {
        // Empty entry password is valid (entry just has no password yet)
        try verifyPasswordRoundTrip(Data(), label: "empty")
    }

    @Test("3b. Password edge case: 1000 characters")
    func password1000Chars() throws {
        let pw = Data(String(repeating: "Aa1!Xx9@", count: 125).utf8) // 1000 chars
        try verifyPasswordRoundTrip(pw, label: "1000chars")
    }

    @Test("3c. Password edge case: every printable ASCII character")
    func passwordPrintableASCII() throws {
        let printable = String((32...126).map { Character(UnicodeScalar($0)) })
        try verifyPasswordRoundTrip(Data(printable.utf8), label: "printable-ascii")
    }

    @Test("3d. Password edge case: Unicode (emoji, CJK, Arabic, Hebrew)")
    func passwordUnicode() throws {
        let pw = "🔐パスワード密码كلمةسر סיסמה 🗝️🛡️"
        try verifyPasswordRoundTrip(Data(pw.utf8), label: "unicode")
    }

    @Test("3e. Password edge case: only spaces")
    func passwordSpaces() throws {
        try verifyPasswordRoundTrip(Data("          ".utf8), label: "spaces")
    }

    // =========================================================================
    // MARK: - 4. Rapid Sequential Operations (1000 iterations)
    // =========================================================================

    @Test("4. Rapid sequential: 1000 iterations of add/list/get + periodic save")
    func rapidSequential() throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let path = dir.appendingPathComponent("rapid.kdbx").path
        let password = Data("RapidTest!".utf8)

        let engine = VaultEngine()
        try engine.create(password: password)

        var allUUIDs: [String] = []

        for i in 0..<1000 {
            // addEntry
            let uuid = try engine.addEntry(
                title: "Rapid\(i)", username: "u\(i)",
                password: Data("pw\(i)".utf8), url: "", notes: ""
            )
            allUUIDs.append(uuid)

            // listEntries
            let list = try engine.listEntries()
            #expect(list.count == i + 1, "List count wrong at iteration \(i)")

            // getEntry (pick a random existing entry)
            let pickIdx = Int.random(in: 0...i)
            let detail = try engine.getEntry(uuid: allUUIDs[pickIdx])
            #expect(detail.title == "Rapid\(pickIdx)")
            #expect(detail.password == Data("pw\(pickIdx)".utf8))

            // Periodic save every 200 iterations
            if (i + 1) % 200 == 0 {
                try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: password)
            }
        }

        // Final save
        try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: password)
        engine.close()

        // Reopen and verify all 1000 entries
        let engine2 = VaultEngine()
        try engine2.open(path: path, password: password)
        defer { engine2.close() }

        let entries = try engine2.listEntries()
        #expect(entries.count == 1000, "Expected 1000 entries, got \(entries.count)")

        // Spot-check 50 random entries for data integrity
        for _ in 0..<50 {
            let idx = Int.random(in: 0..<1000)
            let detail = try engine2.getEntry(uuid: allUUIDs[idx])
            #expect(detail.title == "Rapid\(idx)", "Title mismatch at \(idx)")
            #expect(detail.password == Data("pw\(idx)".utf8), "Password mismatch at \(idx)")
        }
    }

    // =========================================================================
    // MARK: - 5. Disk Full Simulation
    // =========================================================================

    @Test("5. Disk full: save fails cleanly, original untouched")
    func diskFull() throws {
        // Strategy: create a small RAM disk, fill it to capacity with POSIX
        // write(), then attempt an atomicSave.  Falls back to a read-only
        // directory test if the RAM disk cannot be created.

        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }

        // 4 MB RAM disk (8192 × 512-byte sectors).  After HFS+ overhead
        // (~1.5 MB) this leaves ~2.5 MB usable — enough for the tiny vault
        // but easy to fill completely.
        var device = ""
        var usingRamDisk = false
        if let raw = try? runProcess("/usr/bin/hdiutil", "attach", "-nomount", "ram://8192") {
            device = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let _ = try? runProcess("/usr/sbin/diskutil", "erasevolume", "HFS+", "CitadelStress", device) {
                usingRamDisk = true
            } else {
                _ = try? runProcess("/usr/bin/hdiutil", "detach", device, "-force")
                device = ""
            }
        }
        defer {
            if usingRamDisk {
                _ = try? runProcess("/usr/bin/hdiutil", "detach", device, "-force")
            }
        }

        let volumePath = "/Volumes/CitadelStress"
        let testDir: String
        if usingRamDisk {
            testDir = volumePath
        } else {
            testDir = dir.appendingPathComponent("readonly-test").path
            try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        }

        let vaultPath = testDir + "/vault.kdbx"
        let password = Data("DiskFullTest!".utf8)

        // Create vault and add entries
        let engine = VaultEngine()
        try engine.create(password: password)
        for i in 0..<10 {
            _ = try engine.addEntry(
                title: "Entry\(i)", username: "u\(i)",
                password: Data("pw\(i)".utf8), url: "", notes: ""
            )
        }
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)

        // Record original state
        let origData = try Data(contentsOf: URL(fileURLWithPath: vaultPath))

        if usingRamDisk {
            // Fill the RAM disk using POSIX write() — no buffering.
            // Use progressively smaller chunks to leave zero slack.
            let fillerPath = testDir + "/filler.bin"
            let fd = Darwin.open(fillerPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                defer { Darwin.close(fd) }

                // Large chunks first
                var buf = [UInt8](repeating: 0xFF, count: 65536)
                while Darwin.write(fd, &buf, buf.count) > 0 {}

                // Medium chunks
                var med = [UInt8](repeating: 0xFF, count: 4096)
                while Darwin.write(fd, &med, med.count) > 0 {}

                // Tiny chunks to fill the last few KB
                var tiny = [UInt8](repeating: 0xFF, count: 512)
                while Darwin.write(fd, &tiny, tiny.count) > 0 {}

                // Single bytes to fill the last block
                var one: UInt8 = 0xFF
                while Darwin.write(fd, &one, 1) > 0 {}

                // Force metadata flush
                _ = fcntl(fd, F_FULLFSYNC)
            }
        } else {
            // Make directory read-only so .tmp write fails
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: testDir)
        }
        defer {
            if !usingRamDisk {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testDir)
            }
        }

        // Add more entries in memory (not yet saved)
        for i in 10..<30 {
            _ = try engine.addEntry(
                title: "Extra\(i)", username: "x\(i)",
                password: Data(String(repeating: "x", count: 500).utf8),
                url: "", notes: String(repeating: "note", count: 500)
            )
        }

        // Attempt save — should fail
        var saveFailed = false
        do {
            try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)
        } catch {
            saveFailed = true
        }
        #expect(saveFailed, "Save should have failed on full/read-only disk")

        // Original vault untouched
        let afterData = try Data(contentsOf: URL(fileURLWithPath: vaultPath))
        #expect(origData == afterData, "Original vault bytes changed after failed save")

        // Original still openable with correct entry count
        engine.close()
        if !usingRamDisk {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testDir)
        }
        let engine2 = VaultEngine()
        try engine2.open(path: vaultPath, password: password)
        let entries = try engine2.listEntries()
        #expect(entries.count == 10, "Expected 10 entries in original vault, got \(entries.count)")
        engine2.close()
    }

    // =========================================================================
    // MARK: - 6. Round-Trip Fidelity
    // =========================================================================

    @Test("6. Round-trip: fixture saved without changes preserves all data")
    func roundTripFidelity() throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let outputPath = dir.appendingPathComponent("roundtrip.kdbx").path

        // Open fixture and snapshot all entry data
        let engine1 = VaultEngine()
        try engine1.open(path: fixturePath(), password: fixturePassword)

        let origList = try engine1.listEntries()
        var origDetails: [String: VaultEntryDetail] = [:]
        for entry in origList {
            origDetails[entry.id] = try engine1.getEntry(uuid: entry.id)
        }

        // Save to new path (no modifications)
        try engine1.saveTo(path: outputPath)
        engine1.close()

        // Validate the output file
        try VaultEngine.validate(path: outputPath, password: fixturePassword)

        // Reopen and compare every field
        let engine2 = VaultEngine()
        try engine2.open(path: outputPath, password: fixturePassword)
        defer { engine2.close() }

        let newList = try engine2.listEntries()
        #expect(newList.count == origList.count, "Entry count changed: \(origList.count) → \(newList.count)")

        let newByID = Dictionary(uniqueKeysWithValues: newList.map { ($0.id, $0) })
        for (uuid, orig) in origDetails {
            guard newByID[uuid] != nil else {
                Issue.record("Entry \(uuid) (\(orig.title)) missing after round-trip")
                continue
            }
            let new = try engine2.getEntry(uuid: uuid)
            #expect(new.title == orig.title, "Title mismatch: \(orig.title)")
            #expect(new.username == orig.username, "Username mismatch: \(orig.title)")
            #expect(new.password == orig.password, "Password mismatch: \(orig.title)")
            #expect(new.url == orig.url, "URL mismatch: \(orig.title)")
            #expect(new.notes == orig.notes, "Notes mismatch: \(orig.title)")
        }

        // KeePassXC verification
        verifyWithKeePassXC(path: outputPath, password: "Test123")
    }

    // =========================================================================
    // MARK: - 7. Password Change Stress (20 iterations)
    // =========================================================================

    @Test("7. Password change: 20 sequential changes with verify")
    func passwordChangeStress() throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let path = dir.appendingPathComponent("pwchange.kdbx").path
        var currentPw = Data("InitialPassword!0".utf8)

        // Create vault with some entries
        let engine = VaultEngine()
        try engine.create(password: currentPw)
        for i in 0..<5 {
            _ = try engine.addEntry(
                title: "Entry\(i)", username: "u\(i)",
                password: Data("secret\(i)".utf8), url: "", notes: ""
            )
        }
        try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: currentPw)
        engine.close()

        for round in 1...20 {
            let newPw = Data("ChangedPassword!\(round)".utf8)

            // Open with current password
            let eng = VaultEngine()
            try eng.open(path: path, password: currentPw)

            // Change password
            try eng.changePassword(newPw)

            // Save with new password
            try VaultPersistence.atomicSave(engine: eng, vaultPath: path, password: newPw)
            eng.close()

            // Verify: old password fails
            #expect(throws: VaultError.wrongPassword) {
                try VaultEngine.validate(path: path, password: currentPw)
            }

            // Verify: new password works and data intact
            let verify = VaultEngine()
            try verify.open(path: path, password: newPw)
            let entries = try verify.listEntries()
            #expect(entries.count == 5, "Round \(round): expected 5 entries, got \(entries.count)")
            verify.close()

            currentPw = newPw
        }

        // Final: validate and KeePassXC check
        try VaultEngine.validate(path: path, password: currentPw)
        verifyWithKeePassXC(path: path, password: "ChangedPassword!20")
    }

    // =========================================================================
    // MARK: - 8. Snapshot Integrity
    // =========================================================================

    @Test("8. Snapshots: 10 saves produce exactly 3 valid .prev files")
    func snapshotIntegrity() throws {
        let dir = makeTmpDir()
        defer { try? fm.removeItem(at: dir) }
        let path = dir.appendingPathComponent("vault.kdbx").path
        let password = Data("SnapshotTest!".utf8)

        let engine = VaultEngine()
        try engine.create(password: password)

        // Add an entry so the vault isn't empty
        _ = try engine.addEntry(
            title: "Snap", username: "u", password: Data("pw".utf8), url: "", notes: ""
        )

        // Perform 10 sequential saves
        for i in 0..<10 {
            // Add an entry each round so file content changes
            _ = try engine.addEntry(
                title: "Round\(i)", username: "u\(i)",
                password: Data("r\(i)".utf8), url: "", notes: ""
            )
            try VaultPersistence.atomicSave(engine: engine, vaultPath: path, password: password)
        }
        engine.close()

        // Verify exactly 3 .prev files exist
        let prev1 = path + ".prev"
        let prev2 = path + ".prev2"
        let prev3 = path + ".prev3"
        let prev4 = path + ".prev4"

        #expect(fm.fileExists(atPath: prev1), ".prev should exist")
        #expect(fm.fileExists(atPath: prev2), ".prev2 should exist")
        #expect(fm.fileExists(atPath: prev3), ".prev3 should exist")
        #expect(!fm.fileExists(atPath: prev4), ".prev4 should NOT exist (max 3)")

        // Each .prev file should be a valid openable KDBX
        try VaultEngine.validate(path: prev1, password: password)
        try VaultEngine.validate(path: prev2, password: password)
        try VaultEngine.validate(path: prev3, password: password)

        // Current vault should also be valid with all entries
        let engine2 = VaultEngine()
        try engine2.open(path: path, password: password)
        let entries = try engine2.listEntries()
        // 1 initial + 10 round entries = 11
        #expect(entries.count == 11, "Expected 11 entries in final vault, got \(entries.count)")
        engine2.close()

        // .prev files should have fewer entries (they're older snapshots)
        let prevEngine = VaultEngine()
        try prevEngine.open(path: prev1, password: password)
        let prevEntries = try prevEngine.listEntries()
        #expect(prevEntries.count < entries.count, ".prev should have fewer entries than current")
        prevEngine.close()
    }
}
