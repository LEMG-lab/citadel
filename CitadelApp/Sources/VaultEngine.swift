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
    public func open(path: String, password: Data, keyfilePath: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        _close()
        var outHandle: UnsafeMutableRawPointer?
        let result = path.withCString { cPath in
            password.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> VaultResult in
                let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                if let kf = keyfilePath {
                    return kf.withCString { cKf in
                        vault_open(cPath, ptr, UInt32(password.count), cKf, &outHandle)
                    }
                } else {
                    return vault_open(cPath, ptr, UInt32(password.count), nil, &outHandle)
                }
            }
        }
        try check(result)
        handle = outHandle
    }

    /// Create a new KDBX vault in memory. Use `saveTo` or `VaultPersistence` to persist.
    public func create(password: Data, keyfilePath: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        _close()
        var outHandle: UnsafeMutableRawPointer?
        let result = password.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> VaultResult in
            let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            if let kf = keyfilePath {
                return kf.withCString { cKf in
                    vault_create(ptr, UInt32(password.count), cKf, &outHandle)
                }
            } else {
                return vault_create(ptr, UInt32(password.count), nil, &outHandle)
            }
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
    public static func validate(path: String, password: Data, keyfilePath: String? = nil) throws {
        let result = path.withCString { cPath in
            password.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> VaultResult in
                let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                if let kf = keyfilePath {
                    return kf.withCString { cKf in
                        vault_validate(cPath, ptr, UInt32(password.count), cKf)
                    }
                } else {
                    return vault_validate(cPath, ptr, UInt32(password.count), nil)
                }
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

    /// Change the vault password (and optionally keyfile). Takes effect on next save.
    public func changePassword(_ newPassword: Data, keyfilePath: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = newPassword.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> VaultResult in
            let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            if let kf = keyfilePath {
                return kf.withCString { cKf in
                    vault_change_password(h, ptr, UInt32(newPassword.count), cKf)
                }
            } else {
                return vault_change_password(h, ptr, UInt32(newPassword.count), nil)
            }
        }
        try check(result)
    }

    /// Update the KDF parameters on the open vault. Takes effect on next save.
    public func setKdfParams(memory: UInt64, iterations: UInt64, parallelism: UInt32) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = vault_set_kdf_params(h, memory, iterations, parallelism)
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
                url: cString(item.url),
                group: cString(item.group),
                entryType: cString(item.entry_type),
                tags: cString(item.tags),
                expiryDate: item.expiry_time > 0 ? Date(timeIntervalSince1970: TimeInterval(item.expiry_time)) : nil,
                lastModified: item.last_modified > 0 ? Date(timeIntervalSince1970: TimeInterval(item.last_modified)) : nil,
                isFavorite: item.is_favorite,
                attachmentCount: Int(item.attachment_count)
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

        // Parse custom fields
        var customFields: [CustomField] = []
        if let cfPtr = entry.custom_fields, entry.custom_field_count > 0 {
            for i in 0..<Int(entry.custom_field_count) {
                let cf = cfPtr.advanced(by: i).pointee
                customFields.append(CustomField(
                    key: cString(cf.key),
                    value: cString(cf.value),
                    isProtected: cf.is_protected
                ))
            }
        }

        return VaultEntryDetail(
            uuid: cString(entry.uuid),
            title: cString(entry.title),
            username: cString(entry.username),
            password: passwordData,
            url: cString(entry.url),
            notes: cString(entry.notes),
            otpURI: cString(entry.otp_uri),
            entryType: cString(entry.entry_type),
            customFields: customFields,
            expiryDate: entry.expiry_time > 0 ? Date(timeIntervalSince1970: TimeInterval(entry.expiry_time)) : nil,
            lastModified: entry.last_modified > 0 ? Date(timeIntervalSince1970: TimeInterval(entry.last_modified)) : nil,
            isFavorite: entry.is_favorite
        )
    }

    /// Add a new entry. Returns the UUID string.
    public func addEntry(
        title: String,
        username: String,
        password: Data,
        url: String,
        notes: String,
        otpURI: String = "",
        group: String = "",
        expiryDate: Date? = nil
    ) throws -> String {
        try Self.validateFFIString(title, field: "title")
        try Self.validateFFIString(username, field: "username")
        try Self.validateFFIString(url, field: "url")
        try Self.validateFFIString(notes, field: "notes")
        if !group.isEmpty { try Self.validateFFIString(group, field: "group") }
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var uuidPtr: UnsafeMutablePointer<CChar>?
        let expiry: Int64 = expiryDate.map { Int64($0.timeIntervalSince1970) } ?? 0

        let result = title.withCString { cTitle in
            username.withCString { cUser in
                url.withCString { cUrl in
                    notes.withCString { cNotes in
                        otpURI.withCString { cOtp in
                            group.withCString { cGroup in
                                password.withUnsafeBytes { buf -> VaultResult in
                                    let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                                    let groupPtr: UnsafePointer<CChar>? = group.isEmpty ? nil : cGroup
                                    return vault_add_entry(
                                        h, cTitle, cUser,
                                        ptr, UInt32(password.count),
                                        cUrl, cNotes, cOtp, groupPtr, expiry, &uuidPtr
                                    )
                                }
                            }
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
        notes: String,
        otpURI: String = "",
        expiryDate: Date? = nil
    ) throws {
        try Self.validateFFIString(uuid, field: "uuid")
        try Self.validateFFIString(title, field: "title")
        try Self.validateFFIString(username, field: "username")
        try Self.validateFFIString(url, field: "url")
        try Self.validateFFIString(notes, field: "notes")
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let expiry: Int64 = expiryDate.map { Int64($0.timeIntervalSince1970) } ?? 0
        let result = uuid.withCString { cUuid in
            title.withCString { cTitle in
                username.withCString { cUser in
                    url.withCString { cUrl in
                        notes.withCString { cNotes in
                            otpURI.withCString { cOtp in
                                password.withUnsafeBytes { buf -> VaultResult in
                                    let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                                    return vault_update_entry(
                                        h, cUuid, cTitle, cUser,
                                        ptr, UInt32(password.count),
                                        cUrl, cNotes, cOtp, expiry
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        try check(result)
    }

    /// Delete an entry by UUID (soft-delete: moves to Recycle Bin).
    public func deleteEntry(uuid: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            vault_delete_entry(h, cUuid)
        }
        try check(result)
    }

    /// Permanently remove all entries in the Recycle Bin. Returns the count removed.
    @discardableResult
    public func emptyRecycleBin() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var count: UInt32 = 0
        let result = vault_empty_recyclebin(h, &count)
        try check(result)
        return Int(count)
    }

    /// Get password history for an entry. Returns (password as string, date) pairs.
    public func getEntryHistory(uuid: String) throws -> [(password: String, date: Date)] {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var listPtr: UnsafeMutablePointer<CHistoryList>?
        let result = uuid.withCString { cUuid in
            vault_get_entry_history(h, cUuid, &listPtr)
        }
        try check(result)

        guard let list = listPtr?.pointee else { return [] }
        defer { history_list_free(listPtr) }

        var items: [(password: String, date: Date)] = []
        for i in 0..<Int(list.count) {
            let item = list.items.advanced(by: i).pointee
            let pw = cString(item.password)
            let date = item.timestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(item.timestamp)) : Date.distantPast
            items.append((password: pw, date: date))
        }
        return items
    }

    /// Set or clear the favorite flag on an entry.
    public func setFavorite(uuid: String, favorite: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            vault_set_favorite(h, cUuid, favorite)
        }
        try check(result)
    }

    /// Set a custom field on an entry.
    public func setCustomField(uuid: String, key: String, value: String, isProtected: Bool) throws {
        try Self.validateFFIString(key, field: "key")
        try Self.validateFFIString(value, field: "value")
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            key.withCString { cKey in
                value.withCString { cValue in
                    vault_set_custom_field(h, cUuid, cKey, cValue, isProtected)
                }
            }
        }
        try check(result)
    }

    /// Remove a custom field from an entry.
    public func removeCustomField(uuid: String, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            key.withCString { cKey in
                vault_remove_custom_field(h, cUuid, cKey)
            }
        }
        try check(result)
    }

    /// List all group paths in the vault.
    public func listGroups() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var groupsPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var count: UInt32 = 0
        let result = vault_list_groups(h, &groupsPtr, &count)
        try check(result)
        defer { group_list_free(groupsPtr, count) }

        var groups: [String] = []
        if let ptr = groupsPtr {
            for i in 0..<Int(count) {
                if let cStr = ptr.advanced(by: i).pointee {
                    groups.append(String(cString: cStr))
                }
            }
        }
        return groups
    }

    // MARK: - Attachments

    /// List attachments on an entry. Returns (name, sizeBytes) pairs.
    public func listAttachments(uuid: String) throws -> [(name: String, size: Int)] {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var listPtr: UnsafeMutablePointer<CAttachmentList>?
        let result = uuid.withCString { cUuid in
            vault_list_attachments(h, cUuid, &listPtr)
        }
        try check(result)

        guard let list = listPtr?.pointee else { return [] }
        defer { attachment_list_free(listPtr) }

        var items: [(name: String, size: Int)] = []
        for i in 0..<Int(list.count) {
            let item = list.items.advanced(by: i).pointee
            items.append((name: cString(item.name), size: Int(item.size)))
        }
        return items
    }

    /// Get an attachment's raw data by name.
    public func getAttachment(uuid: String, name: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        var dataPtr: UnsafeMutablePointer<CAttachmentData>?
        let result = uuid.withCString { cUuid in
            name.withCString { cName in
                vault_get_attachment(h, cUuid, cName, &dataPtr)
            }
        }
        try check(result)

        guard let att = dataPtr?.pointee else { return Data() }
        defer { attachment_data_free(dataPtr) }

        if let ptr = att.data, att.len > 0 {
            return Data(bytes: ptr, count: Int(att.len))
        }
        return Data()
    }

    /// Add an attachment to an entry.
    public func addAttachment(uuid: String, name: String, data: Data) throws {
        try Self.validateFFIString(name, field: "attachment name")
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            name.withCString { cName in
                data.withUnsafeBytes { buf -> VaultResult in
                    let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    return vault_add_attachment(h, cUuid, cName, ptr, UInt64(data.count))
                }
            }
        }
        try check(result)
    }

    /// Remove an attachment from an entry by name.
    public func removeAttachment(uuid: String, name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let h = try _requireHandle()
        let result = uuid.withCString { cUuid in
            name.withCString { cName in
                vault_remove_attachment(h, cUuid, cName)
            }
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
