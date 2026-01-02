//
//  DuetInputBar.swift
//  DuetChat
//
//  A floating input bar with text and voice input.
//  Collapses to a grab bar, expands on interaction.
//

#if os(iOS)

import SwiftUI
import Speech
import AVFoundation

// MARK: - Duet Input Bar

public struct DuetInputBar: View {
    // Configuration
    let config: DuetConfig
    
    // Bindings
    @Binding var submittedText: String
    @Binding var isProcessing: Bool
    @Binding var showChat: Bool
    @Binding var isCollapsed: Bool
    
    // Internal state
    @State private var inputText: String = ""
    @State private var isRecording: Bool = false
    @FocusState private var isFocused: Bool
    
    // Speech recognition
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine: AVAudioEngine?
    
    public init(
        config: DuetConfig = DuetConfig(),
        submittedText: Binding<String>,
        isProcessing: Binding<Bool>,
        showChat: Binding<Bool>,
        isCollapsed: Binding<Bool>
    ) {
        self.config = config
        self._submittedText = submittedText
        self._isProcessing = isProcessing
        self._showChat = showChat
        self._isCollapsed = isCollapsed
    }
    
    public var body: some View {
        VStack(spacing: 4) {
            // Grab bar - pull up to open chat directly
            grabBar
            
            // Floating pill input - hidden when collapsed
            if !isCollapsed {
                inputPill
            }
        }
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
        .background(Color(.systemBackground))
        .onAppear {
            setupSpeechRecognition()
        }
    }
    
    // MARK: - Grab Bar
    
    private var grabBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                if isCollapsed {
                    isCollapsed = false
                }
                showChat = true
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        if value.translation.height < -15 {
                            if isCollapsed {
                                isCollapsed = false
                            }
                            showChat = true
                        }
                    }
            )
    }
    
    // MARK: - Input Pill
    
    private var inputPill: some View {
        HStack(spacing: 10) {
            // Chat button
            Button {
                showChat = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Text input
            TextField(config.placeholder, text: $inputText, axis: .vertical)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($isFocused)
                .disabled(isProcessing || isRecording)
                .onSubmit {
                    submitInput()
                }
            
            // Action buttons
            HStack(spacing: 6) {
                // Microphone
                if config.enableVoice && !isProcessing {
                    Button {
                        toggleRecording()
                    } label: {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 14))
                            .foregroundColor(isRecording ? .red : .secondary)
                    }
                }
                
                // Submit
                Button {
                    submitInput()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(inputText.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                            .clipShape(Circle())
                    }
                }
                .disabled(inputText.isEmpty || isProcessing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    // MARK: - Actions
    
    private func submitInput() {
        if isRecording {
            stopRecording()
        }
        
        let textToSubmit = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSubmit.isEmpty else { return }
        
        isFocused = false
        inputText = ""
        submittedText = textToSubmit
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
        } catch {
            return
        }
        
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

#endif // os(iOS)

