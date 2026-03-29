import Foundation
import CCitadelCore

/// Safe Swift wrapper around the citadel_core FFI.
///
/// - Passwords are passed and returned as `Data` (byte buffers), never `String`.
/// - `vault_close` is called on `deinit` to zero sensitive memory.
/// - All VaultResult codes are translated to `VaultError`.
/// - All handle operations are serialized via an internal lock, making
///   concurrent access from multiple threads safe.
public final class VaultEngine: @unchecked Sendable {

    private var handle: UnsafeMutableRawPointer?
    private let lock = NSLock()

    /// True when a vault is open and the handle is valid.
    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handle != nil
    }

    public init() {}

    deinit {
        _close()
    }

    // MARK: - Lifecycle

    /// Open an existing KDBX vault file.
    public func open(path: String, password: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        _close()
        var outHandle: UnsafeMutableRawPointer?
        let result = path.withCString { cPath in
            password.withUnsafeBytes { buf -> VaultResult in
                let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return vault_open(cPath, ptr, UInt32(password.count), &outHandle)
            }
        }
        try check(result)
        handle = outHandle
    }

    /// Create a new KDBX vault in memory. Use `saveTo` or `VaultPersistence` to persist.
    public func create(password: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        _close()
        var outHandle: UnsafeMutableRawPointer?
        let result = password.withUnsafeBytes { buf -> VaultResult in
            let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return vault_create(ptr, UInt32(password.count), &outHandle)
        }
        try check(result)
        handle = outHandle
    }

    /// Save the vault to a file path.
    ///
    /// This writes directly to the given path (non-atomic).
    /// Use `VaultPersistence` for the atomic save pipeline.
    /// Internal: only VaultPersistence should call this.
    func saveTo(path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = path.withCString { cPath in
            vault_save_to(h, cPath)
        }
        try check(result)
    }

    /// Validate that a file can be opened with the given password.
    public static func validate(path: String, password: Data) throws {
        let result = path.withCString { cPath in
            password.withUnsafeBytes { buf -> VaultResult in
                let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return vault_validate(cPath, ptr, UInt32(password.count))
            }
        }
        try check(result)
    }

    /// Close the vault and zero sensitive memory.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        _close()
    }

    /// Change the vault password. Takes effect on next save.
    public func changePassword(_ newPassword: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = newPassword.withUnsafeBytes { buf -> VaultResult in
            let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return vault_change_password(h, ptr, UInt32(newPassword.count))
        }
        try check(result)
    }

    // MARK: - Entry Operations

    /// List all entries (no passwords).
    public func listEntries() throws -> [VaultEntrySummary] {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var listPtr: UnsafeMutablePointer<CEntryList>?
        let result = vault_list_entries(h, &listPtr)
        try check(result)

        guard let list = listPtr?.pointee else { return [] }
        defer { entry_list_free(listPtr) }

        var entries: [VaultEntrySummary] = []
        entries.reserveCapacity(Int(list.count))

        for i in 0..<Int(list.count) {
            let item = list.entries.advanced(by: i).pointee
            entries.append(VaultEntrySummary(
                id: cString(item.uuid),
                title: cString(item.title),
                username: cString(item.username),
                url: cString(item.url)
            ))
        }
        return entries
    }

    /// Get full entry details including password (as Data).
    public func getEntry(uuid: String) throws -> VaultEntryDetail {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var entryPtr: UnsafeMutablePointer<CEntryData>?
        let result = uuid.withCString { cUuid in
            vault_get_entry(h, cUuid, &entryPtr)
        }
        try check(result)

        guard let entry = entryPtr?.pointee else {
            throw VaultError.internalError("null entry data")
        }
        defer { entry_data_free(entryPtr) }

        let passwordData: Data
        if let pwPtr = entry.password, entry.password_len > 0 {
            passwordData = Data(bytes: pwPtr, count: Int(entry.password_len))
        } else {
            passwordData = Data()
        }

        return VaultEntryDetail(
            uuid: cString(entry.uuid),
            title: cString(entry.title),
            username: cString(entry.username),
            password: passwordData,
            url: cString(entry.url),
            notes: cString(entry.notes)
        )
    }

    /// Add a new entry. Returns the UUID string.
    public func addEntry(
        title: String,
        username: String,
        password: Data,
        url: String,
        notes: String
    ) throws -> String {
        try Self.validateFFIString(title, field: "title")
        try Self.validateFFIString(username, field: "username")
        try Self.validateFFIString(url, field: "url")
        try Self.validateFFIString(notes, field: "notes")
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var uuidPtr: UnsafeMutablePointer<CChar>?

        let result = title.withCString { cTitle in
            username.withCString { cUser in
                url.withCString { cUrl in
                    notes.withCString { cNotes in
                        password.withUnsafeBytes { buf -> VaultResult in
                            let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                            return vault_add_entry(
                                h, cTitle, cUser,
                                ptr, UInt32(password.count),
                                cUrl, cNotes, &uuidPtr
                            )
                        }
                    }
                }
            }
        }
        try check(result)

        guard let uuidCStr = uuidPtr else {
            throw VaultError.internalError("null uuid after add")
        }
        let uuidString = String(cString: uuidCStr)
        string_free(uuidCStr)
        return uuidString
    }

    /// Update an existing entry by UUID.
    public func updateEntry(
        uuid: String,
        title: String,
        username: String,
        password: Data,
        url: String,
        notes: String
    ) throws {
        try Self.validateFFIString(uuid, field: "uuid")
        try Self.validateFFIString(title, field: "title")
        try Self.validateFFIString(username, field: "username")
        try Self.validateFFIString(url, field: "url")
        try Self.validateFFIString(notes, field: "notes")
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            title.withCString { cTitle in
                username.withCString { cUser in
                    url.withCString { cUrl in
                        notes.withCString { cNotes in
                            password.withUnsafeBytes { buf -> VaultResult in
                                let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                                return vault_update_entry(
                                    h, cUuid, cTitle, cUser,
                                    ptr, UInt32(password.count),
                                    cUrl, cNotes
                                )
                            }
                        }
                    }
                }
            }
        }
        try check(result)
    }

    /// Delete an entry by UUID.
    public func deleteEntry(uuid: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            vault_delete_entry(h, cUuid)
        }
        try check(result)
    }

    // MARK: - Password Generation

    /// Generate a random password. Returns raw bytes.
    public static func generatePassword(length: Int, charset: UInt32) throws -> Data {
        var buf = Data(count: length + 1) // +1 for null terminator space
        let result = buf.withUnsafeMutableBytes { raw -> VaultResult in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return generate_password(
                UInt32(length), charset,
                ptr, UInt32(length + 1)
            )
        }
        try check(result)
        return buf.prefix(length)
    }

    // MARK: - Internal

    /// Close without acquiring the lock. For use within already-locked sections and deinit.
    private func _close() {
        if let h = handle {
            vault_close(h)
            handle = nil
        }
    }

    /// Require a valid handle. Caller must hold the lock.
    private func _requireHandle() throws -> UnsafeMutableRawPointer {
        guard let h = handle else {
            throw VaultError.internalError("vault not open")
        }
        return h
    }

    private static func check(_ result: VaultResult) throws {
        switch result {
        case VAULT_RESULT_OK:
            return
        case VAULT_RESULT_WRONG_PASSWORD:
            throw VaultError.wrongPassword
        case VAULT_RESULT_FILE_CORRUPTED:
            throw VaultError.fileCorrupted
        case VAULT_RESULT_FILE_NOT_FOUND:
            throw VaultError.fileNotFound
        case VAULT_RESULT_WRITE_FAILED:
            throw VaultError.writeFailed
        case VAULT_RESULT_VALIDATION_FAILED:
            throw VaultError.validationFailed
        case VAULT_RESULT_EMPTY_PASSWORD:
            throw VaultError.emptyPassword
        default:
            throw VaultError.internalError("FFI error code \(result.rawValue)")
        }
    }

    private func check(_ result: VaultResult) throws {
        try Self.check(result)
    }

    private func cString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr = ptr else { return "" }
        return String(cString: ptr)
    }

    /// Reject strings containing null bytes — withCString silently truncates at \0.
    private static func validateFFIString(_ s: String, field: String) throws {
        if s.utf8.contains(0) {
            throw VaultError.internalError("\(field) contains null bytes")
        }
    }
}
