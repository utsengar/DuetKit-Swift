//
//  DuetTypes.swift
//  DuetChat
//
//  Shared types for the DuetChat components.
//

#if os(iOS)

import Foundation

// MARK: - Chat Message

/// A message in the chat conversation.
public struct DuetMessage: Identifiable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    public var metadata: [String: String]?
    
    public enum Role: Equatable {
        case user
        case assistant
        case system
    }
    
    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Chat Result

/// Result from processing a user message.
public struct DuetResult {
    public let message: String?
    public let actionsApplied: Int
    public let success: Bool
    public let error: String?
    public let rawResponse: String?  // Raw LLM response for applying actions
    
    public init(
        message: String? = nil,
        actionsApplied: Int = 0,
        success: Bool = true,
        error: String? = nil,
        rawResponse: String? = nil
    ) {
        self.message = message
        self.actionsApplied = actionsApplied
        self.success = success
        self.error = error
        self.rawResponse = rawResponse
    }
    
    public static func success(message: String?, actionsApplied: Int = 0, rawResponse: String? = nil) -> DuetResult {
        DuetResult(message: message, actionsApplied: actionsApplied, success: true, rawResponse: rawResponse)
    }
    
    public static func failure(_ error: String) -> DuetResult {
        DuetResult(success: false, error: error)
    }
}

// MARK: - Configuration

/// Configuration for DuetChat components.
public struct DuetConfig {
    public let title: String
    public let placeholder: String
    public let systemPrompt: String
    public let enableVoice: Bool
    public let collapseOnScroll: Bool
    
    public init(
        title: String = "Chat",
        placeholder: String = "Ask anything...",
        systemPrompt: String = "Ask me to help you.",
        enableVoice: Bool = true,
        collapseOnScroll: Bool = true
    ) {
        self.title = title
        self.placeholder = placeholder
        self.systemPrompt = systemPrompt
        self.enableVoice = enableVoice
        self.collapseOnScroll = collapseOnScroll
    }
}

#endif // os(iOS)

