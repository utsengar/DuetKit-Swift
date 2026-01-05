//
//  DuetCLI.swift
//  DuetCLI
//
//  A command-line tool to try out Duet's Schema and Document system.
//  Engineers can use this to test schemas and JSON Patch operations
//  without needing to run a full iOS app.
//
//  Usage:
//    swift run DuetCLI              # Interactive mode
//    swift run DuetCLI --demo       # Run demo with sample schema
//    swift run DuetCLI --help       # Show help
//

import Foundation
import Duet

// MARK: - Entry Point

@main
struct DuetCLI {
    static func main() {
        let args = CommandLine.arguments
        
        if args.contains("--help") || args.contains("-h") {
            printHeader()
            printHelp()
        } else if args.contains("--budget") {
            printHeader()
            runInteractiveMode(schema: budgetSchema)
        } else if args.contains("--fitness") {
            printHeader()
            runInteractiveMode(schema: fitnessSchema)
        } else {
            // Default to demo mode
            runDemo()
        }
    }
}

// MARK: - CLI Storage (in-memory for CLI)

struct CLIStorage: StorageProvider {
    func save(key: String, value: String) {
        // In CLI mode, we don't persist
    }
    func load(key: String) -> String? { nil }
    func remove(key: String) {}
}

// MARK: - Example Schemas

let budgetSchema = Schema(
    name: "Monthly Budget",
    fields: [
        .number("income", label: "Monthly Income", default: 5000, min: 0, max: 1000000),
        .number("rent", label: "Rent", default: 1500, min: 0),
        .number("groceries", label: "Groceries", default: 400, min: 0),
        .number("utilities", label: "Utilities", default: 150, min: 0),
        .number("savings", label: "Savings Goal", default: 500, min: 0),
        .boolean("autoSave", label: "Auto-transfer to savings", default: true),
        .enum("priority", label: "Savings Priority", options: ["low", "medium", "high"], default: "medium")
    ]
)

let fitnessSchema = Schema(
    name: "Fitness Tracker",
    fields: [
        .number("targetCalories", label: "Daily Calorie Target", default: 2000, min: 1000, max: 5000),
        .number("proteinGoal", label: "Protein Goal (g)", default: 150, min: 0, max: 500),
        .number("stepsGoal", label: "Daily Steps Goal", default: 10000, min: 0),
        .enum("activityLevel", label: "Activity Level", options: ["sedentary", "light", "moderate", "active", "very_active"]),
        .boolean("trackWater", label: "Track Water Intake", default: true)
    ]
)

// MARK: - CLI Functions

func printHeader() {
    print("""
    
    ╔═══════════════════════════════════════════════════════════════╗
    ║                      🎹 Duet CLI                              ║
    ║       Test Schema, Documents, and LLM Bridge locally          ║
    ╚═══════════════════════════════════════════════════════════════╝
    
    """)
}

func printHelp() {
    print("""
    Usage: DuetCLI [options]
    
    Options:
      --demo        Run interactive demo with sample schemas
      --budget      Use the budget schema
      --fitness     Use the fitness schema
      --help, -h    Show this help message
    
    In interactive mode, you can:
      • View current document state
      • Apply JSON Patch operations
      • See the LLM context that would be sent to an AI
      • Test validation rules
    
    Example JSON Patch:
      [{"op": "replace", "path": "/income", "value": 6000}]
    
    """)
}

func printDocument(_ doc: Document) {
    print("\n📄 Document: \(doc.schema.name)")
    print("─────────────────────────────────────────")
    for field in doc.schema.fields {
        let value = doc.get(field.id)
        let valueStr: String
        if let v = value {
            valueStr = String(describing: v)
        } else {
            valueStr = "(not set)"
        }
        print("  \(field.label): \(valueStr)")
    }
    print("─────────────────────────────────────────\n")
}

func printLLMContext(_ bridge: LLMBridge) {
    print("\n🤖 LLM Context (what the AI sees):")
    print("═════════════════════════════════════════")
    print(bridge.getContext())
    print("═════════════════════════════════════════\n")
}

func runInteractiveMode(schema: Schema) {
    let doc = Document(schema: schema, storageKey: "cli-demo", storage: CLIStorage())
    let bridge = LLMBridge(document: doc)
    
    printDocument(doc)
    
    print("Commands:")
    print("  view       - Show current document state")
    print("  context    - Show LLM context")
    print("  schema     - Show schema description")
    print("  patch      - Apply a JSON Patch")
    print("  set        - Quick set a field (e.g., 'set income 7000')")
    print("  history    - Show patch history")
    print("  export     - Export document as JSON")
    print("  quit       - Exit")
    print("")
    
    while true {
        print("> ", terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            continue
        }
        
        let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        
        switch command {
        case "quit", "exit", "q":
            print("Goodbye! 👋")
            return
            
        case "view", "show", "v":
            printDocument(doc)
            
        case "context", "ctx", "c":
            printLLMContext(bridge)
            
        case "schema", "s":
            print("\n\(schema.description)")
            
        case "patch", "p":
            print("Enter JSON Patch (or 'cancel'):")
            print("Example: [{\"op\": \"replace\", \"path\": \"/income\", \"value\": 6000}]")
            print("patch> ", terminator: "")
            if let patchInput = readLine(), patchInput.lowercased() != "cancel" {
                let result = doc.applyJSON(patchInput)
                if result.success {
                    print("✅ Applied \(result.applied) operation(s)")
                    printDocument(doc)
                } else {
                    print("❌ Error: \(result.error ?? "Unknown error")")
                }
            }
            
        case "set":
            if parts.count > 1 {
                let setParts = parts[1].split(separator: " ", maxSplits: 1).map(String.init)
                if setParts.count == 2 {
                    let fieldId = setParts[0]
                    let valueStr = setParts[1]
                    
                    // Try to parse value
                    let value: Any
                    if let num = Double(valueStr) {
                        value = num
                    } else if valueStr.lowercased() == "true" {
                        value = true
                    } else if valueStr.lowercased() == "false" {
                        value = false
                    } else {
                        value = valueStr
                    }
                    
                    // Create and apply patch
                    let patch = [JsonPatchOp(op: "replace", path: "/\(fieldId)", value: value)]
                    let result = doc.applyPatch(patch)
                    if result.success {
                        print("✅ Set \(fieldId) = \(value)")
                    } else {
                        print("❌ Error: \(result.error ?? "Unknown error")")
                    }
                } else {
                    print("Usage: set <fieldId> <value>")
                }
            } else {
                print("Usage: set <fieldId> <value>")
                print("Example: set income 7000")
            }
            
        case "history", "h":
            let history = doc.history()
            if history.isEmpty {
                print("No patch history yet.")
            } else {
                print("\n📜 Patch History:")
                for entry in history {
                    let ops = entry.patch.map { "\($0.op) \($0.path)" }.joined(separator: ", ")
                    let status = entry.result.success ? "✅" : "❌"
                    print("  \(status) [\(entry.source)] \(ops)")
                }
                print("")
            }
            
        case "export", "e":
            print("\n📤 Exported JSON:")
            print(doc.exportJSON())
            print("")
            
        case "help", "?":
            print("""
            
            Commands:
              view, v       - Show current document state
              context, c    - Show LLM context
              schema, s     - Show schema description  
              patch, p      - Apply a JSON Patch interactively
              set <f> <v>   - Quick set a field value
              history, h    - Show patch history
              export, e     - Export document as JSON
              help, ?       - Show this help
              quit, q       - Exit
            
            """)
            
        default:
            print("Unknown command: \(command). Type 'help' for available commands.")
        }
    }
}

func runDemo() {
    printHeader()
    
    print("Select a schema to try:")
    print("  1. Monthly Budget")
    print("  2. Fitness Tracker")
    print("")
    print("Choice (1 or 2): ", terminator: "")
    
    let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
    
    let schema: Schema
    switch choice {
    case "2":
        schema = fitnessSchema
    default:
        schema = budgetSchema
    }
    
    print("\nUsing schema: \(schema.name)\n")
    runInteractiveMode(schema: schema)
}

