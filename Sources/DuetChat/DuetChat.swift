//
//  DuetChat.swift
//  DuetChat
//
//  Main entry point - combines input bar and chat sheet.
//  Add this to any view to get AI chat capabilities.
//
//  Usage:
//  ```
//  struct MyView: View {
//      @State var duet = DuetChatState()
//
//      var body: some View {
//          VStack {
//              // Your content
//              MyContent()
//
//              // Add the chat bar at the bottom
//              DuetChatBar(
//                  state: duet,
//                  config: DuetConfig(title: "My Assistant"),
//                  provider: MyLLMProvider()
//              )
//          }
//      }
//  }
//  ```
//

#if os(iOS)

import SwiftUI

// MARK: - Chat State

/// Observable state object for DuetChat.
/// Create one per view that uses chat.
@Observable
public class DuetChatState {
    public var messages: [DuetMessage] = []
    public var isProcessing: Bool = false
    public var showChat: Bool = false
    public var isCollapsed: Bool = false
    public var submittedText: String = ""
    
    public init() {}
    
    /// Reset the chat state
    public func reset() {
        messages.removeAll()
        isProcessing = false
        submittedText = ""
    }
}

// MARK: - Chat Bar (Main Component)

/// The main DuetChat component. Add this to your view.
public struct DuetChatBar: View {
    @Bindable var state: DuetChatState
    let config: DuetConfig
    let provider: any DuetChatProvider
    let contextProvider: (any DuetContextProvider)?
    let onSubmit: ((String) -> Void)?
    
    public init(
        state: DuetChatState,
        config: DuetConfig = DuetConfig(),
        provider: any DuetChatProvider,
        contextProvider: (any DuetContextProvider)? = nil,
        onSubmit: ((String) -> Void)? = nil
    ) {
        self.state = state
        self.config = config
        self.provider = provider
        self.contextProvider = contextProvider
        self.onSubmit = onSubmit
    }
    
    public var body: some View {
        DuetInputBar(
            config: config,
            submittedText: $state.submittedText,
            isProcessing: $state.isProcessing,
            showChat: $state.showChat,
            isCollapsed: $state.isCollapsed
        )
        .onChange(of: state.submittedText) { _, newValue in
            guard !newValue.isEmpty else { return }
            handleSubmit(newValue)
        }
        .sheet(isPresented: $state.showChat) {
            DuetChatSheet(
                config: config,
                provider: provider,
                contextProvider: contextProvider,
                isPresented: $state.showChat,
                messages: $state.messages,
                isProcessing: $state.isProcessing
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func handleSubmit(_ text: String) {
        // Add user message
        state.messages.append(DuetMessage(
            role: .user,
            content: text
        ))
        state.isProcessing = true
        state.showChat = true
        state.submittedText = ""
        
        // Call custom handler if provided
        onSubmit?(text)
        
        // Process with provider
        let context = contextProvider?.getContext()
        let history = state.messages
        let chatProvider = provider
        let contextProv = contextProvider
        
        Task.detached {
            do {
                let result = try await chatProvider.processMessage(text, context: context, history: history)
                
                // Apply actions using raw response if available
                var actionsApplied = result.actionsApplied
                if let cp = contextProv, result.success, let rawResponse = result.rawResponse {
                    actionsApplied = cp.applyActions(rawResponse)
                }
                
                await MainActor.run {
                    if result.success {
                        let content = result.message ?? (actionsApplied > 0 ? "Done! Applied \(actionsApplied) change(s)." : "Done!")
                        state.messages.append(DuetMessage(
                            role: .assistant,
                            content: content,
                            metadata: ["actionsApplied": "\(actionsApplied)"]
                        ))
                    } else {
                        state.messages.append(DuetMessage(
                            role: .assistant,
                            content: "⚠️ \(result.error ?? "Something went wrong")"
                        ))
                    }
                    state.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    state.messages.append(DuetMessage(
                        role: .assistant,
                        content: "⚠️ Error: \(error.localizedDescription)"
                    ))
                    state.isProcessing = false
                }
            }
        }
    }
}

// MARK: - View Modifier for Scroll Collapse

public extension View {
    /// Makes the DuetChat input bar collapse when scrolling.
    func duetCollapseOnScroll(_ state: DuetChatState) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    if !state.isCollapsed {
                        withAnimation(.easeOut(duration: 0.15)) {
                            state.isCollapsed = true
                        }
                    }
                }
        )
    }
}

// MARK: - Preview

#if DEBUG

/// Demo data that the chat can "edit"
@Observable
private class DemoData {
    var name: String = "John Smith"
    var email: String = "john@example.com"
    var age: Int = 25
    var status: String = "active"
}

/// Mock provider that simulates LLM editing the demo data
private struct DemoLLMProvider: DuetChatProvider {
    let data: DemoData
    
    func processMessage(_ message: String, context: String?, history: [DuetMessage]) async throws -> DuetResult {
        try await Task.sleep(for: .seconds(1))
        
        let lower = message.lowercased()
        
        // Simulate LLM understanding and making edits
        await MainActor.run {
            if lower.contains("jane") {
                data.name = "Jane Doe"
            }
            if lower.contains("30") || lower.contains("thirty") {
                data.age = 30
            }
            if lower.contains("inactive") {
                data.status = "inactive"
            }
            if lower.contains("pending") {
                data.status = "pending"
            }
            if lower.contains("active") && !lower.contains("inactive") {
                data.status = "active"
            }
        }
        
        return .success(message: "Done! I've updated the fields based on your request.")
    }
}

/// Demo context provider
private struct DemoContextProvider: DuetContextProvider {
    let data: DemoData
    
    func getContext() -> String {
        """
        Current Contact:
        - name: \(data.name)
        - email: \(data.email)
        - age: \(data.age)
        - status: \(data.status)
        
        You can ask me to change any of these fields.
        """
    }
    
    func applyActions(_ response: String) -> Int { 0 }
}

#Preview("DuetChat Demo") {
    @Previewable @State var chat = DuetChatState()
    @Previewable @State var data = DemoData()
    
    NavigationStack {
        VStack(spacing: 0) {
            Form {
                Section("Contact Info") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(data.name)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(data.email)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Age")
                        Spacer()
                        Text("\(data.age)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(data.status)
                            .foregroundStyle(data.status == "active" ? .green : .orange)
                    }
                }
                
                Section {
                    Text("Try: \"Change name to Jane\" or \"Set age to 30\" or \"Make status inactive\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            DuetChatBar(
                state: chat,
                config: DuetConfig(
                    title: "Contact Assistant",
                    placeholder: "Change name to Jane...",
                    systemPrompt: "Edit contact fields"
                ),
                provider: DemoLLMProvider(data: data),
                contextProvider: DemoContextProvider(data: data)
            )
        }
        .navigationTitle("Contact Form")
    }
}

#endif

#endif // os(iOS)
