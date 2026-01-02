//
//  DuetChatProvider.swift
//  DuetChat
//
//  Protocol for providing chat responses.
//  Implement this to connect your own LLM or backend.
//

#if os(iOS)

import Foundation

// MARK: - Chat Provider Protocol

/// Protocol for handling chat messages.
/// Implement this to connect DuetChat to your LLM or backend.
public protocol DuetChatProvider: Sendable {
    /// Process a user message and return a result.
    /// - Parameters:
    ///   - message: The user's message
    ///   - context: Optional context string (e.g., current data state)
    ///   - history: Previous messages in the conversation
    /// - Returns: A DuetResult with the response
    func processMessage(
        _ message: String,
        context: String?,
        history: [DuetMessage]
    ) async throws -> DuetResult
}

// MARK: - Context Provider Protocol

/// Protocol for providing context to the chat.
/// Implement this to give the LLM information about your app's state.
public protocol DuetContextProvider {
    /// Returns a string description of the current context/state.
    func getContext() -> String
    
    /// Optional: Apply actions from the LLM response.
    /// Return the number of actions successfully applied.
    func applyActions(_ response: String) -> Int
}

// MARK: - Default Context Provider

/// A simple context provider that returns a static string.
public struct StaticContextProvider: DuetContextProvider {
    private let context: String
    
    public init(_ context: String) {
        self.context = context
    }
    
    public func getContext() -> String {
        context
    }
    
    public func applyActions(_ response: String) -> Int {
        0
    }
}

// MARK: - Simple Echo Provider (for testing)

/// A simple provider that echoes back the user's message.
/// Useful for testing the UI without an LLM.
public struct EchoProvider: DuetChatProvider {
    public init() {}
    
    public func processMessage(
        _ message: String,
        context: String?,
        history: [DuetMessage]
    ) async throws -> DuetResult {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(500))
        return .success(message: "You said: \(message)")
    }
}

#endif // os(iOS)

