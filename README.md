# DuetKit

**Shared state for humans and AI.** A Swift toolkit for building apps where humans and LLMs edit the same state, with validation and an audit trail.

## Overview

DuetKit provides two libraries:

- **Duet** - Observable document store with schema validation and JSON Patch support for LLM edits
- **DuetChat** - Drop-in chat UI with text and voice input (protocol-based, works with any LLM)

## See It In Action

Open the source files in Xcode and check the `#Preview` at the bottom of each:

- **`Sources/Duet/SchemaForm.swift`** — Auto-generated form from schema
- **`Sources/DuetChat/DuetChat.swift`** — Chat UI that edits fields (try "Change name to Jane")

## Installation

Add DuetKit to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/utsengar/duet-kit-swift", from: "1.0.0")
]
```

Then import what you need:

```swift
import Duet      // Schema, Document, LLMBridge
import DuetChat  // Chat UI components
```

## Quick Start

### Duet (State Management)

```swift
import SwiftUI
import Duet

// 1. Define your schema
let budgetSchema = Schema(
    name: "Budget",
    fields: [
        .number("income", label: "Monthly Income", min: 0),
        .number("rent", label: "Rent", min: 0),
        .number("savings", label: "Target Savings %", min: 0, max: 100),
    ]
)

// 2. Create a document
@State private var doc = Document(
    schema: budgetSchema,
    storageKey: "myApp.budget",
    storage: UserDefaultsStorage()
)

// 3. Use in SwiftUI
TextField("Income", text: doc.binding(for: "income"))

// 4. LLM edits via JSON Patch
let bridge = LLMBridge(document: doc)
bridge.getContext()                    // Schema + values for prompt
bridge.applyLLMResponse(jsonPatch)     // Apply LLM's JSON Patch response
```

### DuetChat (Chat UI)

```swift
import SwiftUI
import DuetChat

struct MyView: View {
    @State private var chat = DuetChatState()
    
    var body: some View {
        VStack {
            // Your content
            MyContent()
            
            // Add chat bar
            DuetChatBar(
                state: chat,
                config: DuetConfig(title: "Assistant"),
                provider: MyLLMProvider(),
                contextProvider: MyContextProvider()
            )
        }
    }
}

// Implement the provider protocol
struct MyLLMProvider: DuetChatProvider {
    func processMessage(_ message: String, context: String?, history: [DuetMessage]) async throws -> DuetResult {
        // Call your LLM here
        let response = try await callLLM(message, context: context)
        return .success(message: response.text, rawResponse: response.json)
    }
}
```

## Duet Features

- **@Observable** — Uses iOS 17+ Observation framework
- **Schema validation** — Types and constraints enforced on all edits
- **JSON Patch (RFC 6902)** — Standard format LLMs already know
- **Audit trail** — Every patch logged with timestamp and source
- **Pluggable storage** — UserDefaults, or implement your own `StorageProvider`

## DuetChat Features

- **Floating input bar** — Collapses on scroll, expands on tap
- **Voice input** — Built-in speech recognition
- **Protocol-based** — Bring your own LLM via `DuetChatProvider`
- **Context injection** — Pass app state via `DuetContextProvider`

## Wiring Duet + DuetChat Together

```swift
import Duet
import DuetChat

// Context provider bridges Document to chat
struct DocumentContextProvider: DuetContextProvider {
    let document: Document
    
    func getContext() -> String {
        LLMBridge(document: document).getContext()
    }
    
    func applyActions(_ response: String) -> Int {
        LLMBridge(document: document).applyLLMResponse(response).editsCount
    }
}

// Use in your view
DuetChatBar(
    state: chat,
    provider: myLLMProvider,
    contextProvider: DocumentContextProvider(document: doc)
)
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+

## License

MIT

