//
//  ConductionValidating.swift
//  Pods
//
//  Created by Leif Meyer on 7/19/17.
//
//

import Foundation
import Bindable

public protocol ConductionHumanReadable {
   var humanReadableString: String { get }
}

public extension ConductionHumanReadable where Self: RawRepresentable, Self.RawValue == String {
   var humanReadableString: String { return rawValue }
}

public enum ConductionValidationError: Error {
   case values(selfType: String, message: String, errors: [(key: String, message: String)])
   case consistency(selfType: String, message: String, errors: [(keys: [String], message: String)])
   
   // MARK: - Public Properties
   public var message: String {
      switch self {
      case .values(_, let message, _): return message
      case .consistency(_, let message, _): return message
      }
   }
   
   public var errors: [(keys: [String], message: String)] {
      switch self {
      case .values(_, _, let errors): return errors.map { return (keys: [$0.key], message: $0.message) }
      case .consistency(_, _, let errors): return errors
      }
   }
   
   // MARK: - Consolidating Errors
   public mutating func consolidate(with errorsForKeys: [(key: String, error: ConductionValidationError)]) {
      guard !errorsForKeys.isEmpty else { return }
      
      switch self {
      case .values(let selfType, let message, var errors):
         errorsForKeys.forEach { key, error in
            switch error {
            case .values(_, _, let subErrors):
               errors.append(contentsOf: subErrors.map { return (key: "\(key).\($0.key)", message: $0.message) })
            case .consistency: return
            }
         }
         self = .values(selfType: selfType, message: message, errors: errors)
      case .consistency(let selfType, let message, var errors):
         errorsForKeys.forEach { key, error in
            switch error {
            case .values: return
            case .consistency(_, _, let subErrors):
               errors.append(contentsOf: subErrors.map { return (keys: $0.keys.map { "\(key).\($0)" }, message: $0.message) })
            }
         }
         self = .consistency(selfType: selfType, message: message, errors: errors)
      }
   }
}

public protocol ConductionValidating {
   var validationError: ConductionValidationError? { get }
}

public protocol KVConductionValidating: ConductionValidating, IncKVCompliance {
   func keyPassesDefaultValidation(_  key: Key) -> Bool
   func validationErrorMessageForKey(_  key: Key) -> String?
   var consistencyErrorKeyGroups: [[Key]] { get }
   var consistencyErrorMessages: [(keys: [Key], message: String)] { get }
   var validatingKeys: [Key] { get }
   var validationContext: String { get }
   var errorsForKeys: [(key: String, error: ConductionValidationError)] { get }
}

public extension KVConductionValidating {
   func keyPassesDefaultValidation(_  key: Key) -> Bool { return true }
   func validationErrorMessageForKey(_  key: Key) -> String? {
      guard !keyPassesDefaultValidation(key) else { return nil }
      let keyName = (key as? ConductionHumanReadable)?.humanReadableString ?? key.rawValue
      return keyName.isEmpty ? "Invalid value." : "\(keyName): Invalid value."
   }
   var consistencyErrorKeyGroups: [[Key]] { return [] }
   var consistencyErrorMessages: [(keys: [Key], message: String)] { return consistencyErrorKeyGroups.map {
      let messageKey = $0.map { ($0 as? ConductionHumanReadable)?.humanReadableString ?? $0.rawValue }.joined(separator: ", ")
      return (keys: $0, message: messageKey.isEmpty ? "Conflicting values." : "\(messageKey): Conflicting values.") }
   }
   var validatingKeys: [Key] { return [] }
   var validationContext: String { return (self as? ConductionHumanReadable)?.humanReadableString ?? "\(type(of: self))" }
   var errorsForKeys: [(key: String, error: ConductionValidationError)] {
      var errorsForKeys: [(key: String, error: ConductionValidationError)] = []
      return validatingKeys.flatMap {
         guard let value = self[$0] as? ConductionValidating, let error = value.validationError else { return nil }
         return (key: $0.rawValue, error: error)
      }
      return errorsForKeys
   }
   
   var validationError: ConductionValidationError? {
      let subErrors = errorsForKeys
      var invalidErrors: [(key: String, message: String)] = []
      Key.all.forEach {
         guard let errorMessage = validationErrorMessageForKey($0) else { return }
         invalidErrors.append((key: $0.rawValue, message: errorMessage))
      }
      let hasValueSubErrors = !subErrors.filter {
         switch $1 {
         case .values: return true
         case .consistency: return false
         }
         }.isEmpty
      
      guard invalidErrors.isEmpty, !hasValueSubErrors else {
         var validationError: ConductionValidationError = .values(selfType: "\(type(of: self))", message: validationContext, errors: invalidErrors)
         validationError.consolidate(with: subErrors)
         return validationError
      }
      
      var consistencyErrors: [(keys: [String], message: String)] = []
      consistencyErrorMessages.forEach {
         let keyStrings = $0.keys.map { return $0.rawValue }
         consistencyErrors.append((keys: keyStrings, message: $0.message))
      }
      guard consistencyErrors.isEmpty, subErrors.isEmpty else {
         var validationError: ConductionValidationError = .consistency(selfType: "\(type(of: self))", message: validationContext, errors: consistencyErrors)
         validationError.consolidate(with: subErrors)
         return validationError
      }
      return nil
   }
}
