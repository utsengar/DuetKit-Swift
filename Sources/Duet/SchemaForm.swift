//
//  SchemaForm.swift
//  Duet
//
//  Auto-generated SwiftUI form from a Schema.
//  Provides standard input controls based on field types.
//
//  Note: UI components are iOS-only due to iOS-specific APIs.
//  Uses @available to provide helpful compiler errors on unsupported platforms.
//

import Foundation

// MARK: - In-Memory Storage (for previews and testing)

public struct InMemoryStorage: StorageProvider {
    public init() {}
    
    public func save(key: String, value: String) {}
    public func load(key: String) -> String? { nil }
    public func remove(key: String) {}
}

// MARK: - UserDefaults Storage (common implementation)

public struct UserDefaultsStorage: StorageProvider {
    public init() {}
    
    public func save(key: String, value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    public func load(key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }
    
    public func remove(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - SwiftUI Form Components (iOS only)

#if os(iOS)

import SwiftUI

// MARK: - Auto-Generated Form

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "SchemaForm is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct SchemaForm: View {
    @Bindable var document: Document
    public var sections: [FormSection]? = nil
    
    public init(document: Document, sections: [FormSection]? = nil) {
        self.document = document
        self.sections = sections
    }
    
    public var body: some View {
        Form {
            if let sections = sections {
                // Custom sections
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.fieldIds, id: \.self) { fieldId in
                            if let field = document.schema.field(named: fieldId) {
                                fieldView(for: field)
                            }
                        }
                    }
                }
            } else {
                // Default: all fields in one section
                ForEach(document.schema.fields, id: \.id) { field in
                    fieldView(for: field)
                }
            }
            
            // Show error if any
            if let error = document.lastError {
                Section {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
    }
    
    @ViewBuilder
    private func fieldView(for field: Field) -> some View {
        switch field.type {
        case .text:
            TextFieldRow(document: document, field: field)
        case .number:
            NumberFieldRow(document: document, field: field)
        case .boolean:
            ToggleRow(document: document, field: field)
        case .enum(let options):
            PickerRow(document: document, field: field, options: options)
        case .date:
            DateRow(document: document, field: field)
        }
    }
}

// MARK: - Form Section

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "FormSection is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct FormSection {
    public let title: String
    public let fieldIds: [String]
    
    public init(title: String, fieldIds: [String]) {
        self.title = title
        self.fieldIds = fieldIds
    }
}

// MARK: - Individual Field Views

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "TextFieldRow is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct TextFieldRow: View {
    @Bindable var document: Document
    let field: Field
    
    public init(document: Document, field: Field) {
        self.document = document
        self.field = field
    }
    
    public var body: some View {
        HStack {
            Text(field.label)
            Spacer()
            TextField("", text: document.binding(for: field.id))
                .multilineTextAlignment(.trailing)
        }
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "NumberFieldRow is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct NumberFieldRow: View {
    @Bindable var document: Document
    let field: Field
    
    @State private var textValue: String = ""
    
    public init(document: Document, field: Field) {
        self.document = document
        self.field = field
    }
    
    public var body: some View {
        HStack {
            Text(field.label)
            Spacer()
            TextField("", text: $textValue)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .onChange(of: textValue) { _, newValue in
                    if let num = Double(newValue) {
                        _ = document.tryEdit(field.id, value: num)
                    }
                }
            
            // Show unit hint from validation
            if let validation = field.validation {
                if let min = validation.min, let max = validation.max {
                    Text("(\(Int(min))-\(Int(max)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            let num = document.getNumber(field.id)
            textValue = num == 0 ? "" : String(format: "%.0f", num)
        }
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "ToggleRow is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct ToggleRow: View {
    @Bindable var document: Document
    let field: Field
    
    public init(document: Document, field: Field) {
        self.document = document
        self.field = field
    }
    
    public var body: some View {
        Toggle(field.label, isOn: document.boolBinding(for: field.id))
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "PickerRow is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct PickerRow: View {
    @Bindable var document: Document
    let field: Field
    let options: [String]
    
    public init(document: Document, field: Field, options: [String]) {
        self.document = document
        self.field = field
        self.options = options
    }
    
    public var body: some View {
        Picker(field.label, selection: document.binding(for: field.id)) {
            ForEach(options, id: \.self) { option in
                Text(option.capitalized).tag(option)
            }
        }
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "DateRow is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct DateRow: View {
    @Bindable var document: Document
    let field: Field
    
    @State private var date = Date()
    
    public init(document: Document, field: Field) {
        self.document = document
        self.field = field
    }
    
    public var body: some View {
        DatePicker(field.label, selection: $date, displayedComponents: .date)
            .onChange(of: date) { _, newValue in
                _ = document.tryEdit(field.id, value: newValue)
            }
            .onAppear {
                if let storedDate: Date = document.get(field.id) {
                    date = storedDate
                }
            }
    }
}

// MARK: - Standalone Field Components (for custom layouts)

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "DocumentTextField is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct DocumentTextField: View {
    @Bindable var document: Document
    let fieldId: String
    var placeholder: String = ""
    
    public init(document: Document, fieldId: String, placeholder: String = "") {
        self.document = document
        self.fieldId = fieldId
        self.placeholder = placeholder
    }
    
    public var body: some View {
        TextField(placeholder, text: document.binding(for: fieldId))
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "DocumentNumberField is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct DocumentNumberField: View {
    @Bindable var document: Document
    let fieldId: String
    var placeholder: String = ""
    
    @State private var textValue: String = ""
    
    public init(document: Document, fieldId: String, placeholder: String = "") {
        self.document = document
        self.fieldId = fieldId
        self.placeholder = placeholder
    }
    
    public var body: some View {
        TextField(placeholder, text: $textValue)
            .keyboardType(.decimalPad)
            .onChange(of: textValue) { _, newValue in
                if let num = Double(newValue) {
                    _ = document.tryEdit(fieldId, value: num)
                }
            }
            .onAppear {
                let num = document.getNumber(fieldId)
                textValue = num == 0 ? "" : String(format: "%.0f", num)
            }
    }
}

@available(iOS 17.0, *)
@available(macOS, unavailable, message: "DocumentToggle is only available on iOS")
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct DocumentToggle: View {
    @Bindable var document: Document
    let fieldId: String
    let label: String
    
    public init(document: Document, fieldId: String, label: String) {
        self.document = document
        self.fieldId = fieldId
        self.label = label
    }
    
    public var body: some View {
        Toggle(label, isOn: document.boolBinding(for: fieldId))
    }
}

// MARK: - Preview Example

#if DEBUG

/// Example schema for previews - shows all field types
private let exampleSchema = Schema(
    name: "Contact",
    fields: [
        .text("name", label: "Full Name"),
        .text("email", label: "Email"),
        .number("age", label: "Age", default: 25, min: 1, max: 150),
        .enum("status", label: "Status", options: ["active", "inactive", "pending"])
    ]
)

@available(iOS 17.0, *)
#Preview("SchemaForm Example") {
    @Previewable @State var doc = Document(
        schema: exampleSchema,
        storageKey: "preview.contact",
        storage: InMemoryStorage()
    )
    
    NavigationStack {
        SchemaForm(document: doc)
            .navigationTitle("Contact Form")
    }
}

#endif // DEBUG

#endif // os(iOS)
