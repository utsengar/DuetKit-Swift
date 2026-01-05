//
//  Document.swift
//  Duet
//
//  Observable document store that both humans (via UI) and LLMs can edit.
//  Provides validation and change notifications.
//  Storage is pluggable - app injects the storage provider.
//
//  Uses JSON Patch (RFC 6902) for LLM edits.
//
//  Note: SwiftUI bindings are in Document+UI.swift
//

import Foundation

// MARK: - Storage Provider Protocol

/// Protocol for pluggable storage. App injects the implementation.
public protocol StorageProvider {
    func save(key: String, value: String)
    func load(key: String) -> String?
    func remove(key: String)
}

// MARK: - JSON Patch (RFC 6902)

/// JSON Patch operation (RFC 6902)
public struct JsonPatchOp: Codable {
    public let op: String      // "replace", "add", "remove"
    public let path: String    // "/fieldName" or "/nested/field"
    public let value: AnyCodable?
    
    public init(op: String, path: String, value: Any? = nil) {
        self.op = op
        self.path = path
        self.value = value.map { AnyCodable($0) }
    }
}

/// Result of applying a patch
public struct PatchResult {
    public let success: Bool
    public let applied: Int
    public let error: String?
    
    public init(success: Bool, applied: Int, error: String?) {
        self.success = success
        self.applied = applied
        self.error = error
    }
    
    public static func success(applied: Int) -> PatchResult {
        PatchResult(success: true, applied: applied, error: nil)
    }
    
    public static func failure(_ error: String) -> PatchResult {
        PatchResult(success: false, applied: 0, error: error)
    }
}

/// Entry in the patch history (audit trail)
public struct PatchHistoryEntry: Identifiable {
    public let id: String
    public let timestamp: Date
    public let patch: [JsonPatchOp]
    public let source: String  // "user", "llm", "system"
    public let result: PatchResult
    
    public init(id: String, timestamp: Date, patch: [JsonPatchOp], source: String, result: PatchResult) {
        self.id = id
        self.timestamp = timestamp
        self.patch = patch
        self.source = source
        self.result = result
    }
}

// MARK: - Document Store

@Observable
public class Document {
    public let schema: Schema
    public let storageKey: String
    public let storage: StorageProvider
    
    public private(set) var data: [String: Any]
    public private(set) var lastError: SchemaError?
    
    /// Patch history (audit trail)
    public private(set) var patchHistory: [PatchHistoryEntry] = []
    private var historyIdCounter = 0
    
    /// Fields that were recently updated (for visual feedback)
    public var recentlyUpdatedFields: Set<String> = []
    
    /// Update counter to trigger SwiftUI refreshes
    public private(set) var updateCount: Int = 0
    
    /// Incremented when UI should show highlights (e.g., when chat closes)
    public var highlightTrigger: Int = 0
    
    /// Call this to trigger highlight animations for recently updated fields
    public func triggerHighlights() {
        highlightTrigger += 1
    }
    
    public init(schema: Schema, storageKey: String, storage: StorageProvider) {
        self.schema = schema
        self.storageKey = storageKey
        self.storage = storage
        self.data = [:]
        
        // Load persisted data or use defaults
        if let loaded = Self.load(key: storageKey, storage: storage) {
            self.data = loaded
        } else {
            self.data = schema.defaultValues()
        }
    }
    
    /// Check if a field was recently updated
    public func wasRecentlyUpdated(_ fieldId: String) -> Bool {
        recentlyUpdatedFields.contains(fieldId)
    }
    
    /// Clear recently updated status for a field
    public func clearRecentlyUpdated(_ fieldId: String) {
        recentlyUpdatedFields.remove(fieldId)
    }
    
    /// Clear all recently updated fields
    public func clearAllRecentlyUpdated() {
        recentlyUpdatedFields.removeAll()
    }
    
    // MARK: - Read Operations
    
    public func get<T>(_ fieldId: String) -> T? {
        data[fieldId] as? T
    }
    
    public func get(_ fieldId: String) -> Any? {
        data[fieldId]
    }
    
    public func getString(_ fieldId: String) -> String {
        (data[fieldId] as? String) ?? ""
    }
    
    public func getNumber(_ fieldId: String) -> Double {
        if let d = data[fieldId] as? Double { return d }
        if let i = data[fieldId] as? Int { return Double(i) }
        return 0
    }
    
    public func getBool(_ fieldId: String) -> Bool {
        (data[fieldId] as? Bool) ?? false
    }
    
    // MARK: - Write Operations (Single Field)
    
    /// Edit a single field. Validates against schema before applying.
    public func edit(_ fieldId: String, value: Any) throws {
        try schema.validate(fieldId: fieldId, value: value)
        data[fieldId] = value
        lastError = nil
        persist()
    }
    
    /// Edit without throwing - stores error for UI display
    public func tryEdit(_ fieldId: String, value: Any) -> Bool {
        do {
            try edit(fieldId, value: value)
            return true
        } catch let error as SchemaError {
            lastError = error
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - JSON Patch (RFC 6902)
    
    /// Apply JSON Patch operations. Returns result with count of applied ops.
    @discardableResult
    public func applyPatch(_ ops: [JsonPatchOp], source: String = "llm") -> PatchResult {
        print("[Document] applyPatch called with \(ops.count) ops")
        var updatedFields: Set<String> = []
        var appliedCount = 0
        
        // Validate all operations first
        for op in ops {
            let fieldId = extractFieldId(from: op.path)
            print("[Document] Processing op: \(op.op) path=\(op.path) fieldId=\(fieldId) value=\(String(describing: op.value?.value))")
            
            guard op.op == "replace" || op.op == "add" else {
                let result = PatchResult.failure("Unsupported operation: \(op.op)")
                logPatch(ops, source: source, result: result)
                return result
            }
            
            guard let value = op.value?.value else {
                print("[Document] Missing value for \(op.path)")
                let result = PatchResult.failure("Missing value for \(op.path)")
                logPatch(ops, source: source, result: result)
                return result
            }
            
            // Validate against schema
            do {
                try schema.validate(fieldId: fieldId, value: value)
            } catch let error as SchemaError {
                let result = PatchResult.failure(error.localizedDescription)
                logPatch(ops, source: source, result: result)
                return result
            } catch {
                let result = PatchResult.failure(error.localizedDescription)
                logPatch(ops, source: source, result: result)
                return result
            }
        }
        
        // Apply all operations - build new data dictionary to ensure @Observable triggers
        var newData = data
        for op in ops {
            let fieldId = extractFieldId(from: op.path)
            if let value = op.value?.value {
                // Handle nested paths like /accommodation/type
                if op.path.split(separator: "/").count > 2 {
                    newData = applyNestedValueToDict(newData, path: op.path, value: value)
                } else {
                    newData[fieldId] = value
                }
                updatedFields.insert(fieldId)
                appliedCount += 1
                print("[Document] Updated \(fieldId) to \(value)")
            }
        }
        
        // Reassign data to trigger @Observable
        data = newData
        
        // Update state
        lastError = nil
        recentlyUpdatedFields = updatedFields
        updateCount += 1
        print("[Document] updateCount is now \(updateCount)")
        persist()
        
        let result = PatchResult.success(applied: appliedCount)
        logPatch(ops, source: source, result: result)
        return result
    }
    
    /// Apply JSON Patch from string (accepts array or wrapped format)
    @discardableResult
    public func applyJSON(_ json: String, source: String = "llm") -> PatchResult {
        guard let jsonData = json.data(using: .utf8) else {
            return PatchResult.failure("Invalid JSON encoding")
        }
        
        // Try parsing as array first: [{"op": "replace", ...}]
        if let ops = try? JSONDecoder().decode([JsonPatchOp].self, from: jsonData) {
            return applyPatch(ops, source: source)
        }
        
        // Try wrapped format: {"patch": [...]}
        struct WrappedPatch: Codable {
            let patch: [JsonPatchOp]
        }
        if let wrapped = try? JSONDecoder().decode(WrappedPatch.self, from: jsonData) {
            return applyPatch(wrapped.patch, source: source)
        }
        
        // Try legacy format: {"edits": [{"field": "x", "value": y}]}
        if let legacy = try? JSONDecoder().decode(LegacyEditsWrapper.self, from: jsonData) {
            let ops = legacy.edits.map { edit in
                JsonPatchOp(op: "replace", path: "/\(edit.field)", value: edit.value.value)
            }
            return applyPatch(ops, source: source)
        }
        
        return PatchResult.failure("Could not parse JSON Patch")
    }
    
    /// Get patch history (audit trail)
    public func history() -> [PatchHistoryEntry] {
        patchHistory
    }
    
    /// Clear patch history
    public func clearHistory() {
        patchHistory.removeAll()
    }
    
    // MARK: - Private Helpers
    
    /// Extract field ID from JSON Pointer path (e.g., "/income" -> "income")
    private func extractFieldId(from path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        return components.first ?? path
    }
    
    /// Apply value to nested path and return new dictionary (e.g., /accommodation/type)
    private func applyNestedValueToDict(_ dict: [String: Any], path: String, value: Any) -> [String: Any] {
        let components = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard components.count >= 2 else { return dict }
        
        var newDict = dict
        let fieldId = components[0]
        let current = dict[fieldId] as? [String: Any] ?? [:]
        let modified = setNestedValue(in: current, path: Array(components.dropFirst()), value: value)
        newDict[fieldId] = modified
        return newDict
    }
    
    private func setNestedValue(in dict: [String: Any], path: [String], value: Any) -> [String: Any] {
        guard !path.isEmpty else { return dict }
        
        var result = dict
        let key = path[0]
        
        if path.count == 1 {
            result[key] = value
        } else {
            let nested = dict[key] as? [String: Any] ?? [:]
            result[key] = setNestedValue(in: nested, path: Array(path.dropFirst()), value: value)
        }
        
        return result
    }
    
    private func logPatch(_ ops: [JsonPatchOp], source: String, result: PatchResult) {
        historyIdCounter += 1
        let entry = PatchHistoryEntry(
            id: String(historyIdCounter),
            timestamp: Date(),
            patch: ops,
            source: source,
            result: result
        )
        patchHistory.append(entry)
    }
    
    /// Legacy edit format for backwards compatibility
    private struct LegacyEdit: Codable {
        let field: String
        let value: AnyCodable
    }
    
    private struct LegacyEditsWrapper: Codable {
        let edits: [LegacyEdit]
    }
    
    // Legacy support - convert old format to JSON Patch
    public struct Edit: Codable {
        public let field: String
        public let value: AnyCodable
        
        public init(field: String, value: AnyCodable) {
            self.field = field
            self.value = value
        }
    }
    
    public struct EditsWrapper: Codable {
        public let edits: [Edit]
        
        public init(edits: [Edit]) {
            self.edits = edits
        }
    }
    
    /// Legacy method - converts to JSON Patch internally
    public func applyEdits(_ edits: [Edit]) throws {
        let ops = edits.map { edit in
            JsonPatchOp(op: "replace", path: "/\(edit.field)", value: edit.value.value)
        }
        let result = applyPatch(ops, source: "user")
        if !result.success {
            throw DocumentError.editFailed(result.error ?? "Unknown error")
        }
    }
    
    /// Legacy method - converts to JSON Patch internally
    public func applyEditsFromJSON(_ json: String) throws {
        let result = applyJSON(json)
        if !result.success {
            throw DocumentError.editFailed(result.error ?? "Unknown error")
        }
    }
    
    // MARK: - Persistence
    
    private func persist() {
        // Convert to JSON-safe dictionary
        let jsonSafe = makeJSONSafe(data)
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonSafe),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            storage.save(key: storageKey, value: jsonString)
        }
    }
    
    private static func load(key: String, storage: StorageProvider) -> [String: Any]? {
        guard let jsonString = storage.load(key: key),
              let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        return dict
    }
    
    private func makeJSONSafe(_ dict: [String: Any]) -> [String: Any] {
        var safe: [String: Any] = [:]
        for (key, value) in dict {
            if let date = value as? Date {
                safe[key] = date.timeIntervalSince1970
            } else {
                safe[key] = value
            }
        }
        return safe
    }
    
    // MARK: - Export
    
    public func exportJSON() -> String {
        let jsonSafe = makeJSONSafe(data)
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonSafe, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}

// MARK: - Document Errors

public enum DocumentError: LocalizedError {
    case invalidJSON
    case editFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON format"
        case .editFailed(let reason):
            return "Edit failed: \(reason)"
        }
    }
}

// MARK: - AnyCodable (for JSON flexibility)

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encodeNil()
        }
    }
}

