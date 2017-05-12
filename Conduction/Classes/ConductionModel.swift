//
//  ConductionModel.swift
//  Pods
//
//  Created by Leif Meyer on 5/12/17.
//
//

import Foundation
import Bindable

public protocol StringConductionModelType: StringBindable {
   // MARK: – Keys
   var modelReadKeyStrings: [String] { get }
   var modelWriteKeyStrings: [String] { get }
   var viewReadKeyStrings: [String] { get }
   var viewWriteKeyStrings: [String] { get }
   
   func bindings(for keyString: String) -> [Binding]
}

public extension StringConductionModelType {
   // MARK: - Keys
   var modelKeyStrings: [String] { return modelReadKeyStrings + modelWriteKeyStrings }
   var viewKeyStrings: [String] { return modelReadKeyStrings + modelWriteKeyStrings }
}

public protocol ConductionModelType: Bindable, StringConductionModelType {
   // MARK: – Keys
   var modelReadKeys: [Key] { get }
   var modelWriteKeys: [Key] { get }
   var viewReadKeys: [Key] { get }
   var viewWriteKeys: [Key] { get }
   
   // MARK: - Bindings
   func bindings(for key: Key) -> [Binding]
}

public extension ConductionModelType {
   // MARK: - Keys
   var modelKeys: [Key] { return modelReadKeys + modelWriteKeys }
   var viewKeys: [Key] { return modelReadKeys + modelWriteKeys }

   // MARK: - Bindings
   func bindings(for keyString: String) -> [Binding] {
      guard let key = Key(rawValue: keyString) else { return [] }
      return bindings(for: key)
   }

   // MARK: - StringConductionModelType Protocol
   var modelReadKeyStrings: [String] {
      return modelReadKeys.map { return $0.rawValue }
   }
   var modelWriteKeyStrings: [String] {
      return modelWriteKeys.map { return $0.rawValue }
   }
   var viewReadKeyStrings: [String] {
      return viewReadKeys.map { return $0.rawValue }
   }
   var viewWriteKeyStrings: [String] {
      return viewWriteKeys.map { return $0.rawValue }
   }
   
}

public protocol ConductionModelState {
   init()
}

public struct ConductionModelEmptyState: ConductionModelState {
   public init() {}
}

open class ConductionModel<Key: IncKVKeyType, State: ConductionModelState>: ConductionModelType {
   // MARK: Public Properties
   public var modelBindings: [Binding]
   public var state: State {
      didSet {
         onStateChange?(state)
      }
   }
   public var onStateChange: ((State) -> Void)?
   open var modelReadOnlyKeys: [Key] { return [] }
   open var modelReadWriteKeys: [Key] { return [] }
   open var modelWriteOnlyKeys: [Key] { return [] }
   open var viewReadOnlyKeys: [Key] { return [] }
   open var viewReadWriteKeys: [Key] { return [] }
   open var viewWriteOnlyKeys: [Key] { return [] }
   
   // MARK: Public
   public func value<T>(for key: Key, default defaultValue: T?) -> T? {
      return value(for: key) as? T ?? defaultValue
   }
   
   // MARK: - Init
   public convenience init() {
      self.init(modelBindings: [])
   }
   public init(model: StringBindable) {
      modelBindings = []
      state = State()
      self.modelBindings = modelKeys.map { return Binding(key: $0, target: model, targetKey: $0) }
   }
   public init(modelBindings: [Binding]) {
      state = State()
      self.modelBindings = modelBindings
   }
   
   // MARK: - Subclass Hooks
   open func conductedValue(for key: Key) -> Any? { return nil }
   open func set(conductedValue: Any?, for key: Key) throws {}
   
   // MARK: - ConductionModelType Protocol
   open var modelReadKeys: [Key] { return modelReadOnlyKeys + modelReadWriteKeys }
   open var modelWriteKeys: [Key] { return modelReadWriteKeys + modelWriteOnlyKeys }
   open var viewReadKeys: [Key] { return viewReadOnlyKeys + viewReadWriteKeys }
   open var viewWriteKeys: [Key] { return viewReadWriteKeys + viewWriteOnlyKeys }
   
   public func bindings(for key: Key) -> [Binding] {
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else { return bindings }
      return [Binding(key: key, target: self, targetKey: key)]
   }
   
   public func bindings<MapKey: IncKVKeyType>(for key: Key, mappedTo mapKey: MapKey) -> [Binding] {
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else { return bindings.map(firstKey: key, toSecondKey: mapKey) }
      return [Binding(key: mapKey, target: self, targetKey: key)]
   }
   
   // MARK: - Bindable Protocol
   public var bindingBlocks: [Key : [((targetObject: AnyObject, rawTargetKey: String)?, Any?) throws -> Bool?]] = [:]
   public var keysBeingSet: [Key] = []
   
   public func value(for key: Key) -> Any? {
      guard modelReadKeys.contains(key) else { return conductedValue(for: key) }
      let bindings = modelBindings.filter(key: key)
      return bindings.last?.targetValue
   }
   
   public func setOwn(value: Any?, for key: Key) throws {
      guard modelWriteKeys.contains(key) else { try set(conductedValue: value, for: key); return }
      let bindings = modelBindings.filter(key: key)
      try bindings.forEach { try $0.set(targetValue: value) }
   }
}
