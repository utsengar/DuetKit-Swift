//
//  DuetChatSheet.swift
//  DuetChat
//
//  Full-screen chat interface with message bubbles.
//  Slides up from the input bar.
//

#if os(iOS)

import SwiftUI
import Speech
import AVFoundation

// MARK: - Chat Sheet View

public struct DuetChatSheet: View {
    // Configuration
    let config: DuetConfig
    let provider: any DuetChatProvider
    let contextProvider: (any DuetContextProvider)?
    
    // Bindings
    @Binding var isPresented: Bool
    @Binding var messages: [DuetMessage]
    @Binding var isParentProcessing: Bool
    
    // Internal state
    @State private var inputText: String = ""
    @State private var isLocalProcessing: Bool = false
    @FocusState private var isInputFocused: Bool
    
    // Speech recognition
    @State private var isRecording: Bool = false
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine: AVAudioEngine?
    
    private var isProcessing: Bool {
        isParentProcessing || isLocalProcessing
    }
    
    public init(
        config: DuetConfig = DuetConfig(),
        provider: any DuetChatProvider,
        contextProvider: (any DuetContextProvider)? = nil,
        isPresented: Binding<Bool>,
        messages: Binding<[DuetMessage]>,
        isProcessing: Binding<Bool>
    ) {
        self.config = config
        self.provider = provider
        self.contextProvider = contextProvider
        self._isPresented = isPresented
        self._messages = messages
        self._isParentProcessing = isProcessing
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .id("processing")
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isProcessing) { _, newValue in
                        if newValue {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                
                Divider()
                
                // Input area
                inputArea
            }
            .navigationTitle(config.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        messages.removeAll()
                        addSystemMessage()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .onAppear {
            if messages.isEmpty || messages.first?.role != .system {
                addSystemMessage()
            }
            isInputFocused = true
            setupSpeechRecognition()
        }
        .onDisappear {
            if isRecording {
                stopRecording()
            }
        }
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .disabled(isProcessing || isRecording)
                .onSubmit {
                    sendMessage()
                }
            
            if config.enableVoice && !isProcessing {
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isRecording ? .red : .secondary)
                }
            }
            
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty || isProcessing ? .gray : .blue)
            }
            .disabled(inputText.isEmpty || isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Helpers
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if isProcessing {
                proxy.scrollTo("processing", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func addSystemMessage() {
        messages.insert(DuetMessage(
            role: .system,
            content: config.systemPrompt
        ), at: 0)
    }
    
    private func sendMessage() {
        if isRecording {
            stopRecording()
        }
        
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let textCopy = String(text)
        
        messages.append(DuetMessage(
            role: .user,
            content: textCopy
        ))
        
        inputText = ""
        isLocalProcessing = true
        
        let context = contextProvider?.getContext()
        let history = messages
        let chatProvider = provider
        
        let contextProv = contextProvider
        
        Task.detached {
            do {
                let result = try await chatProvider.processMessage(textCopy, context: context, history: history)
                
                // Apply actions using raw response
                var actionsApplied = result.actionsApplied
                if let cp = contextProv, result.success, let rawResponse = result.rawResponse {
                    actionsApplied = cp.applyActions(rawResponse)
                }
                
                await MainActor.run {
                    if result.success {
                        let content = result.message ?? (actionsApplied > 0 ? "Done! Applied \(actionsApplied) change(s)." : "Done!")
                        messages.append(DuetMessage(
                            role: .assistant,
                            content: content,
                            metadata: ["actionsApplied": "\(actionsApplied)"]
                        ))
                    } else {
                        messages.append(DuetMessage(
                            role: .assistant,
                            content: "⚠️ \(result.error ?? "Something went wrong")"
                        ))
                    }
                    isLocalProcessing = false
                }
            } catch {
                await MainActor.run {
                    messages.append(DuetMessage(
                        role: .assistant,
                        content: "⚠️ Error: \(error.localizedDescription)"
                    ))
                    isLocalProcessing = false
                }
            }
        }
    }
    
    // MARK: - Speech Recognition
    
    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { return }
                Task { @MainActor in
                    beginRecording()
                }
            }
        }
    }
    
    private func beginRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else { return }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    Task { @MainActor in
                        inputText = result.bestTranscription.formattedString
                    }
                }
                
                if error != nil || result?.isFinal == true {
                    Task { @MainActor in
                        stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
        }
    }
    
    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - Message Bubble

public struct MessageBubble: View {
    public let message: DuetMessage
    
    public init(message: DuetMessage) {
        self.message = message
    }
    
    public var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(18)
            }
            
            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return Color(.systemGray5)
        case .system:
            return Color(.systemGray6)
        }
    }
    
    private var foregroundColor: Color {
        switch message.role {
        case .user:
            return .white
        case .assistant, .system:
            return .primary
        }
    }
}

#endif // os(iOS)

