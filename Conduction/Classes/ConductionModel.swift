//
//  ConductionModel.swift
//  Pods
//
//  Created by Leif Meyer on 5/12/17.
//
//

import Foundation
import Bindable

protocol StringConductionModelType: StringBindable {
   // MARK: – Keys
   var modelKeyStrings: [String] { get }
   var viewKeyStrings: [String] { get }
   
   func bindings(for keyString: String) -> [Binding]
}

protocol ConductionModelType: Bindable, StringConductionModelType {
   // MARK: – Keys
   var modelKeys: [Key] { get }
   var viewKeys: [Key] { get }
   
   // MARK: - Bindings
   func bindings(for key: Key) -> [Binding]
}

extension ConductionModelType {
   var modelKeyStrings: [String] {
      return modelKeys.map { return $0.rawValue }
   }
   var viewKeyStrings: [String] {
      return viewKeys.map { return $0.rawValue }
   }
   
   func bindings(for keyString: String) -> [Binding] {
      guard let key = Key(rawValue: keyString) else { return [] }
      return bindings(for: key)
   }
}

protocol ConductionModelStateType {
   init()
}

struct ConductionModelState: ConductionModelStateType {}

class ConductionModel<Key: IncKVKeyType, State: ConductionModelStateType>: ConductionModelType {
   // MARK: Public Properties
   var modelBindings: [Binding]
   var state: State {
      didSet {
         onStateChange?(state)
      }
   }
   var onStateChange: ((State) -> Void)?
   
   // MARK: Public
   func value<T>(for key: Key, default defaultValue: T?) -> T? {
      return value(for: key) as? T ?? defaultValue
   }
   
   // MARK: - Init
   convenience init() {
      self.init(modelBindings: [])
   }
   init(model: StringBindable) {
      modelBindings = []
      state = State()
      self.modelBindings = modelKeys.map { return Binding(key: $0, target: model, targetKey: $0) }
   }
   init(modelBindings: [Binding]) {
      state = State()
      self.modelBindings = modelBindings
   }
   
   // MARK: - Subclass Hooks
   func conductedValue(for key: Key) -> Any? { return nil }
   func setConducted(value: Any?, for key: Key) throws {}
   
   // MARK: - ConductionModelType Protocol
   var modelKeys: [Key] { return [] }
   var viewKeys: [Key] { return [] }
   
   func bindings(for key: Key) -> [Binding] {
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else { return bindings }
      return [Binding(key: key, target: self, targetKey: key)]
   }
   
   // MARK: - Bindable Protocol
   var bindingBlocks: [Key : [((targetObject: AnyObject, rawTargetKey: String)?, Any?) throws -> Bool?]] = [:]
   var keysBeingSet: [Key] = []
   
   func value(for key: Key) -> Any? {
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else { return bindings.last!.targetValue }
      return conductedValue(for: key)
   }
   
   func setOwn(value: Any?, for key: Key) throws {
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else {
         try bindings.forEach { try $0.set(targetValue: value) }
         return
      }
      try setConducted(value: value, for: key)
   }
}
