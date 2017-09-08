//
//  ConductionValidating.swift
//  Pods
//
//  Created by Leif Meyer on 7/19/17.
//
//

import Foundation
import Bindable

public enum ConductionValidationError: Error {
   case values(selfType: String, keys: [String], message: String, errors: [String : String])
   case consistency(selfType: String, keys: [[String]], message: String, errors: [String : String])
   
   // MARK: - Public Properties
   public var message: String {
      switch self {
      case .values(_, _, let message, _): return message
      case .consistency(_, _, let message, _): return message
      }
   }
   public var errors: [String : String] {
      switch self {
      case .values(_, _, _, let errors): return errors
      case .consistency(_, _, _, let errors): return errors
      }
   }
   
   // MARK: - Consolidating Errors
   public mutating func consolidate(with errorsForKeys: [String : ConductionValidationError]) {
      guard !errorsForKeys.isEmpty else { return }
      
      switch self {
      case .values(let selfType, var keys, let message, var errors):
         errorsForKeys.forEach { key, error in
            switch error {
            case .values(_, let subKeys, _, let subErrors):
               keys.append(contentsOf: subKeys.map { return "\(key).\($0)" })
               subErrors.forEach {
                  errors["\(key).\($0)"] = $1
               }
            case .consistency: return
            }
         }
         self = .values(selfType: selfType, keys: keys, message: message, errors: errors)
      case .consistency(let selfType, var keys, let message, var errors):
         errorsForKeys.forEach { key, error in
            switch error {
            case .values: return
            case .consistency(_, let subKeys, _, let subErrors):
               keys.append(contentsOf: subKeys.map { $0.map { return "\(key).\($0)" } })
               subErrors.forEach {
                  errors["\(key).(\($0))"] = $1
               }
            }
         }
         self = .consistency(selfType: selfType, keys: keys, message: message, errors: errors)
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
   var errorsForKeys: [String : ConductionValidationError] { get }
}

public extension KVConductionValidating {
   func keyPassesDefaultValidation(_  key: Key) -> Bool { return true }
   func validationErrorMessageForKey(_  key: Key) -> String? {
      return keyPassesDefaultValidation(key) ? nil : "Invalid value."
   }
   var consistencyErrorKeyGroups: [[Key]] { return [] }
   var consistencyErrorMessages: [(keys: [Key], message: String)] { return consistencyErrorKeyGroups.map { return ($0, "Conflicting values") } }
   var validatingKeys: [Key] { return [] }
   var validationContext: String { return "\(type(of: self))" }
   var errorsForKeys: [String : ConductionValidationError] {
      var errorsForKeys: [String : ConductionValidationError] = [:]
      validatingKeys.forEach {
         guard let value = self[$0] as? ConductionValidating, let error = value.validationError else { return }
         errorsForKeys[$0.rawValue] = error
      }
      return errorsForKeys
   }
   
   var validationError: ConductionValidationError? {
      let subErrors = errorsForKeys
      var errors: [String : String] = [:]
      var invalidKeys: [Key] = []
      Key.all.forEach {
         guard let errorMessage = validationErrorMessageForKey($0) else { return }
         invalidKeys.append($0)
         errors[$0.rawValue] = errorMessage
      }
      let hasValueSubErrors = !subErrors.filter {
         switch $1 {
         case .values: return true
         case .consistency: return false
         }
         }.isEmpty
      
      guard invalidKeys.isEmpty, !hasValueSubErrors else {
         let keys = invalidKeys.map { return $0.rawValue }
         var validationError: ConductionValidationError = .values(selfType: "\(type(of: self))", keys: keys, message: "\(validationContext) contains invalid values.", errors: errors)
         validationError.consolidate(with: subErrors)
         return validationError
      }
      
      var inconsistentKeyStringGroups: [[String]] = []
      consistencyErrorMessages.forEach {
         let keyStrings = $0.keys.map { return $0.rawValue }
         inconsistentKeyStringGroups.append(keyStrings)
         errors[keyStrings.joined(separator: ",")] = $0.message
      }
      guard inconsistentKeyStringGroups.isEmpty, subErrors.isEmpty else {
         var validationError: ConductionValidationError = .consistency(selfType: "\(type(of: self))", keys: inconsistentKeyStringGroups, message: "\(validationContext) contains conflicting values.", errors: errors)
         validationError.consolidate(with: subErrors)
         return validationError
      }
      return nil
   }
}
