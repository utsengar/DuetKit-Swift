//
//  Document+UI.swift
//  Duet
//
//  SwiftUI bindings for Document.
//  Separated from Document.swift to keep the core data model UI-agnostic.
//

import SwiftUI

// MARK: - SwiftUI Bindings

@available(iOS 17.0, macOS 14.0, *)
public extension Document {
    
    /// Creates a SwiftUI Binding for a string field.
    func binding(for fieldId: String) -> Binding<String> {
        Binding(
            get: { self.getString(fieldId) },
            set: { newValue in
                // For text fields, just set directly
                if self.schema.field(named: fieldId)?.type == .text {
                    _ = self.tryEdit(fieldId, value: newValue)
                } else if self.schema.field(named: fieldId)?.type == .number {
                    // Try to convert to number
                    if let num = Double(newValue) {
                        _ = self.tryEdit(fieldId, value: num)
                    }
                }
            }
        )
    }
    
    /// Creates a SwiftUI Binding for a numeric field.
    func numberBinding(for fieldId: String) -> Binding<Double> {
        Binding(
            get: { self.getNumber(fieldId) },
            set: { newValue in
                _ = self.tryEdit(fieldId, value: newValue)
            }
        )
    }
    
    /// Creates a SwiftUI Binding for a boolean field.
    func boolBinding(for fieldId: String) -> Binding<Bool> {
        Binding(
            get: { self.getBool(fieldId) },
            set: { newValue in
                _ = self.tryEdit(fieldId, value: newValue)
            }
        )
    }
}

