//
//  LLMBridge.swift
//  Duet
//
//  Bridge between LLMs and Documents.
//  Provides context generation and JSON Patch application.
//
//  Uses JSON Patch (RFC 6902) format for edits.
//

import Foundation

// MARK: - LLM Bridge

public struct LLMBridge {
    public let document: Document
    
    public init(document: Document) {
        self.document = document
    }
    
    // MARK: - Context for LLM
    
    /// Generate context string for LLM to understand the document
    public func getContext() -> String {
        """
        Schema: \(document.schema.name)
        Fields:
        \(fieldDescriptions())
        
        Current Values:
        \(currentValuesDescription())
        
        You can:
        1. EDIT fields - when user wants to change values
        2. ANALYZE - when user asks questions, use current values to provide insights
        
        To edit fields, respond with JSON containing:
        - "patch": JSON Patch array (RFC 6902) for edits
        - "message": optional insight or analysis (null if just editing)
        
        JSON Patch format: [{ "op": "replace", "path": "/fieldName", "value": newValue }]
        
        Examples:
        - Edit: {"patch": [{"op": "replace", "path": "/targetCalories", "value": 1800}], "message": null}
        - Insight only: {"patch": [], "message": "Based on your current values..."}
        - Both: {"patch": [{"op": "replace", "path": "/interestRate", "value": 5.5}], "message": "This saves $200/month"}
        """
    }
    
    /// Shorter context for constrained prompts
    public func getCompactContext() -> String {
        """
        Document: \(document.schema.name)
        Fields: \(document.schema.fields.map { "\($0.id)=\(document.get($0.id) ?? "nil")" }.joined(separator: ", "))
        Edit: [{"op": "replace", "path": "/field", "value": X}]
        """
    }
    
    private func fieldDescriptions() -> String {
        document.schema.fields.map { field in
            var desc = "  - \(field.id) (\(field.type)): \(field.label)"
            if let validation = field.validation {
                if let min = validation.min { desc += ", min: \(min)" }
                if let max = validation.max { desc += ", max: \(max)" }
            }
            return desc
        }.joined(separator: "\n")
    }
    
    private func currentValuesDescription() -> String {
        document.schema.fields.map { field in
            let value = document.get(field.id)
            let valueStr: String
            if let v = value {
                if let dict = v as? [String: Any],
                   let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    valueStr = jsonStr
                } else {
                    valueStr = String(describing: v)
                }
            } else {
                valueStr = "(not set)"
            }
            return "  \(field.id): \(valueStr) (\(field.label))"
        }.joined(separator: "\n")
    }
    
    // MARK: - Apply LLM Edits (JSON Patch)
    
    /// Apply JSON Patch from LLM response. Supports multiple formats:
    /// - `{"patch": [...], "message": "..."}`  (preferred)
    /// - `[{"op": "replace", ...}]` (raw patch array)
    /// - `{"edits": [...]}` (legacy format)
    public func applyLLMResponse(_ jsonResponse: String) -> LLMEditResult {
        print("[LLMBridge] applyLLMResponse called with: \(jsonResponse.prefix(200))...")
        
        guard let data = jsonResponse.data(using: .utf8) else {
            print("[LLMBridge] Invalid JSON encoding")
            return .parseError("Invalid JSON encoding")
        }
        
        // Extract message first (if present)
        let message = extractMessage(from: data)
        
        // Try JSON Patch format: {"patch": [...], "message": "..."}
        struct PatchResponse: Decodable {
            let patch: [JsonPatchOp]
            let message: String?
        }
        do {
            let response = try JSONDecoder().decode(PatchResponse.self, from: data)
            print("[LLMBridge] Decoded PatchResponse with \(response.patch.count) ops")
            let result = document.applyPatch(response.patch, source: "llm")
            print("[LLMBridge] applyPatch result: success=\(result.success), applied=\(result.applied)")
            if result.success {
                return .success(editsApplied: result.applied, llmMessage: response.message ?? message)
            } else {
                return .validationError(result.error ?? "Unknown error")
            }
        } catch {
            print("[LLMBridge] PatchResponse decode failed: \(error)")
        }
        
        // Try raw patch array: [{"op": "replace", ...}]
        if let ops = try? JSONDecoder().decode([JsonPatchOp].self, from: data) {
            let result = document.applyPatch(ops, source: "llm")
            if result.success {
                return .success(editsApplied: result.applied, llmMessage: message)
            } else {
                return .validationError(result.error ?? "Unknown error")
            }
        }
        
        // Try legacy format: {"edits": [{"field": "x", "value": y}]}
        struct LegacyResponse: Decodable {
            let edits: [Document.Edit]
            let message: String?
        }
        if let response = try? JSONDecoder().decode(LegacyResponse.self, from: data) {
            let ops = response.edits.map { edit in
                JsonPatchOp(op: "replace", path: "/\(edit.field)", value: edit.value.value)
            }
            let result = document.applyPatch(ops, source: "llm")
            if result.success {
                return .success(editsApplied: result.applied, llmMessage: response.message ?? message)
            } else {
                return .validationError(result.error ?? "Unknown error")
            }
        }
        
        return .parseError("Could not parse LLM response as JSON Patch")
    }
    
    private func extractMessage(from data: Data) -> String? {
        struct MessageOnly: Decodable {
            let message: String?
        }
        return (try? JSONDecoder().decode(MessageOnly.self, from: data))?.message
    }
    
    /// Get patch history from document
    public func history() -> [PatchHistoryEntry] {
        document.history()
    }
    
    /// Clear patch history
    public func clearHistory() {
        document.clearHistory()
    }
    
    // MARK: - Function Calling Interface (JSON Patch)
    
    /// Schema for OpenAI/Anthropic function calling (JSON Patch format)
    public var functionSchema: [String: Any] {
        [
            "name": "edit_\(document.schema.name.lowercased().replacingOccurrences(of: " ", with: "_"))",
            "description": "Edit fields in the \(document.schema.name) document using JSON Patch (RFC 6902)",
            "parameters": [
                "type": "object",
                "properties": [
                    "patch": [
                        "type": "array",
                        "description": "JSON Patch operations (RFC 6902)",
                        "items": [
                            "type": "object",
                            "properties": [
                                "op": [
                                    "type": "string",
                                    "enum": ["replace", "add"],
                                    "description": "Operation type"
                                ],
                                "path": [
                                    "type": "string",
                                    "description": "JSON Pointer path (e.g., /fieldName)",
                                    "pattern": "^/.*"
                                ],
                                "value": [
                                    "oneOf": [
                                        ["type": "string"],
                                        ["type": "number"],
                                        ["type": "boolean"],
                                        ["type": "object"]
                                    ],
                                    "description": "New value"
                                ]
                            ],
                            "required": ["op", "path", "value"]
                        ]
                    ],
                    "message": [
                        "type": "string",
                        "description": "Optional message or insight for the user",
                        "nullable": true
                    ]
                ],
                "required": ["patch"]
            ]
        ]
    }
    
    /// Get function schema for OpenAI tools format
    public func getFunctionSchema() -> [String: Any] {
        functionSchema
    }
    
    /// JSON string of function schema for API calls
    public var functionSchemaJSON: String {
        if let data = try? JSONSerialization.data(withJSONObject: functionSchema, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

// MARK: - LLM Edit Result

public enum LLMEditResult {
    case success(editsApplied: Int, llmMessage: String?)
    case validationError(String)
    case parseError(String)
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var editsCount: Int {
        if case .success(let count, _) = self { return count }
        return 0
    }
    
    /// Message from the LLM (insights, analysis)
    public var llmMessage: String? {
        if case .success(_, let msg) = self { return msg }
        return nil
    }
    
    /// Status message about the operation
    public var statusMessage: String {
        switch self {
        case .success(let count, _):
            if count > 0 {
                return "Applied \(count) edit(s)"
            } else {
                return ""
            }
        case .validationError(let msg):
            return "Validation failed: \(msg)"
        case .parseError(let msg):
            return "Could not parse response: \(msg)"
        }
    }
}

// MARK: - Siri/Shortcuts Integration

public extension Document {
    /// Create an intent-compatible summary
    func intentSummary() -> String {
        schema.fields.map { field in
            "\(field.label): \(get(field.id) ?? "not set")"
        }.joined(separator: "\n")
    }
    
    /// Process natural language edit (for Siri/Shortcuts)
    /// Returns a prompt that can be sent to an LLM
    func naturalLanguageEditPrompt(_ userRequest: String) -> String {
        let bridge = LLMBridge(document: self)
        return """
        User request: \(userRequest)
        
        \(bridge.getContext())
        
        Based on the user's request, determine which field(s) to edit and respond with the JSON.
        """
    }
}

// MARK: - MCP (Model Context Protocol) Support

public struct MCPResource {
    public let document: Document
    
    public init(document: Document) {
        self.document = document
    }
    
    /// MCP resource URI
    public var uri: String {
        "kit://documents/\(document.schema.name.lowercased())"
    }
    
    /// MCP resource content
    public var content: String {
        document.exportJSON()
    }
    
    /// MCP tool definition for editing this document
    public var editTool: [String: Any] {
        [
            "name": "edit_\(document.schema.name.lowercased())",
            "description": "Edit the \(document.schema.name) document",
            "inputSchema": LLMBridge(document: document).functionSchema["parameters"] as Any
        ]
    }
}

