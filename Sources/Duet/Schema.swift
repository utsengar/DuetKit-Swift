//
//  Schema.swift
//  Duet
//
//  Schema DSL for defining document structure, validation, and labels.
//  Both humans (via UI) and LLMs can use this schema.
//

import Foundation

// MARK: - Schema Definition

public struct Schema {
    public let name: String
    public let version: Int
    public let fields: [Field]
    
    public init(name: String, version: Int = 1, fields: [Field]) {
        self.name = name
        self.version = version
        self.fields = fields
    }
    
    public func field(named: String) -> Field? {
        fields.first { $0.id == named }
    }
    
    public func validate(fieldId: String, value: Any) throws {
        guard let field = field(named: fieldId) else {
            throw SchemaError.unknownField(fieldId)
        }
        try field.validate(value)
    }
    
    public func defaultValues() -> [String: Any] {
        var defaults: [String: Any] = [:]
        for field in fields {
            if let defaultValue = field.defaultValue {
                defaults[field.id] = defaultValue
            }
        }
        return defaults
    }
}

// MARK: - Field Types

public struct Field {
    public let id: String
    public let label: String
    public let type: FieldType
    public let defaultValue: Any?
    public let validation: FieldValidation?
    
    public init(id: String, label: String, type: FieldType, defaultValue: Any? = nil, validation: FieldValidation? = nil) {
        self.id = id
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.validation = validation
    }
    
    public func validate(_ value: Any) throws {
        // Type check
        switch type {
        case .text:
            guard value is String else {
                throw SchemaError.typeMismatch(field: id, expected: "String", got: String(describing: Swift.type(of: value)))
            }
        case .number:
            guard value is Double || value is Int else {
                throw SchemaError.typeMismatch(field: id, expected: "Number", got: String(describing: Swift.type(of: value)))
            }
        case .boolean:
            guard value is Bool else {
                throw SchemaError.typeMismatch(field: id, expected: "Bool", got: String(describing: Swift.type(of: value)))
            }
        case .enum(let options):
            guard let stringValue = value as? String, options.contains(stringValue) else {
                throw SchemaError.invalidEnumValue(field: id, allowed: options)
            }
        case .date:
            guard value is Date else {
                throw SchemaError.typeMismatch(field: id, expected: "Date", got: String(describing: Swift.type(of: value)))
            }
        }
        
        // Additional validation
        if let validation = validation {
            try validation.validate(value, fieldId: id)
        }
    }
}

public enum FieldType: Equatable {
    case text
    case number
    case boolean
    case `enum`([String])
    case date
}

// MARK: - Field Validation

public struct FieldValidation {
    public var min: Double?
    public var max: Double?
    public var minLength: Int?
    public var maxLength: Int?
    public var pattern: String?
    public var required: Bool
    
    public init(min: Double? = nil, max: Double? = nil, minLength: Int? = nil, maxLength: Int? = nil, pattern: String? = nil, required: Bool = false) {
        self.min = min
        self.max = max
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
        self.required = required
    }
    
    public func validate(_ value: Any, fieldId: String) throws {
        // Number range validation
        if let numValue = value as? Double {
            if let min = min, numValue < min {
                throw SchemaError.belowMinimum(field: fieldId, min: min, got: numValue)
            }
            if let max = max, numValue > max {
                throw SchemaError.aboveMaximum(field: fieldId, max: max, got: numValue)
            }
        }
        if let intValue = value as? Int {
            let numValue = Double(intValue)
            if let min = min, numValue < min {
                throw SchemaError.belowMinimum(field: fieldId, min: min, got: numValue)
            }
            if let max = max, numValue > max {
                throw SchemaError.aboveMaximum(field: fieldId, max: max, got: numValue)
            }
        }
        
        // String length validation
        if let stringValue = value as? String {
            if let minLength = minLength, stringValue.count < minLength {
                throw SchemaError.tooShort(field: fieldId, minLength: minLength)
            }
            if let maxLength = maxLength, stringValue.count > maxLength {
                throw SchemaError.tooLong(field: fieldId, maxLength: maxLength)
            }
        }
    }
}

// MARK: - Schema Errors

public enum SchemaError: LocalizedError {
    case unknownField(String)
    case typeMismatch(field: String, expected: String, got: String)
    case invalidEnumValue(field: String, allowed: [String])
    case belowMinimum(field: String, min: Double, got: Double)
    case aboveMaximum(field: String, max: Double, got: Double)
    case tooShort(field: String, minLength: Int)
    case tooLong(field: String, maxLength: Int)
    case requiredFieldMissing(String)
    
    public var errorDescription: String? {
        switch self {
        case .unknownField(let field):
            return "Unknown field: \(field)"
        case .typeMismatch(let field, let expected, let got):
            return "Field '\(field)' expected \(expected), got \(got)"
        case .invalidEnumValue(let field, let allowed):
            return "Field '\(field)' must be one of: \(allowed.joined(separator: ", "))"
        case .belowMinimum(let field, let min, let got):
            return "Field '\(field)' value \(got) is below minimum \(min)"
        case .aboveMaximum(let field, let max, let got):
            return "Field '\(field)' value \(got) is above maximum \(max)"
        case .tooShort(let field, let minLength):
            return "Field '\(field)' must be at least \(minLength) characters"
        case .tooLong(let field, let maxLength):
            return "Field '\(field)' must be at most \(maxLength) characters"
        case .requiredFieldMissing(let field):
            return "Required field '\(field)' is missing"
        }
    }
}

// MARK: - Field Builder DSL

public extension Field {
    static func text(_ id: String, label: String, default defaultValue: String? = nil, minLength: Int? = nil, maxLength: Int? = nil) -> Field {
        Field(
            id: id,
            label: label,
            type: .text,
            defaultValue: defaultValue,
            validation: (minLength != nil || maxLength != nil) 
                ? FieldValidation(minLength: minLength, maxLength: maxLength) 
                : nil
        )
    }
    
    static func number(_ id: String, label: String, default defaultValue: Double? = nil, min: Double? = nil, max: Double? = nil) -> Field {
        Field(
            id: id,
            label: label,
            type: .number,
            defaultValue: defaultValue,
            validation: (min != nil || max != nil) 
                ? FieldValidation(min: min, max: max) 
                : nil
        )
    }
    
    static func boolean(_ id: String, label: String, default defaultValue: Bool = false) -> Field {
        Field(
            id: id,
            label: label,
            type: .boolean,
            defaultValue: defaultValue,
            validation: nil
        )
    }
    
    static func `enum`(_ id: String, label: String, options: [String], default defaultValue: String? = nil) -> Field {
        Field(
            id: id,
            label: label,
            type: .enum(options),
            defaultValue: defaultValue ?? options.first,
            validation: nil
        )
    }
    
    static func date(_ id: String, label: String, default defaultValue: Date? = nil) -> Field {
        Field(
            id: id,
            label: label,
            type: .date,
            defaultValue: defaultValue,
            validation: nil
        )
    }
}

// MARK: - Schema Description (for LLM context)

public extension Schema {
    var description: String {
        var desc = "Schema: \(name) (v\(version))\n"
        desc += "Fields:\n"
        for field in fields {
            desc += "  - \(field.id) (\(field.type.description)): \(field.label)"
            if let validation = field.validation {
                var constraints: [String] = []
                if let min = validation.min { constraints.append("min: \(min)") }
                if let max = validation.max { constraints.append("max: \(max)") }
                if let minLen = validation.minLength { constraints.append("minLength: \(minLen)") }
                if let maxLen = validation.maxLength { constraints.append("maxLength: \(maxLen)") }
                if !constraints.isEmpty {
                    desc += " [\(constraints.joined(separator: ", "))]"
                }
            }
            desc += "\n"
        }
        return desc
    }
}

public extension FieldType {
    var description: String {
        switch self {
        case .text: return "text"
        case .number: return "number"
        case .boolean: return "boolean"
        case .enum(let options): return "enum(\(options.joined(separator: "|")))"
        case .date: return "date"
        }
    }
}

