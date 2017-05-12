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
   var modelKeyStrings: [String] { get }
   var viewKeyStrings: [String] { get }
   
   func bindings(for keyString: String) -> [Binding]
}

public protocol ConductionModelType: Bindable, StringConductionModelType {
   // MARK: – Keys
   var modelKeys: [Key] { get }
   var viewKeys: [Key] { get }
   
   // MARK: - Bindings
   func bindings(for key: Key) -> [Binding]
}

public extension ConductionModelType {
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
   open var modelKeys: [Key] { return [] }
   open var viewKeys: [Key] { return [] }
   
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
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else { return bindings.last!.targetValue }
      return conductedValue(for: key)
   }
   
   public func setOwn(value: Any?, for key: Key) throws {
      let bindings = modelBindings.filter(key: key)
      guard bindings.isEmpty else {
         try bindings.forEach { try $0.set(targetValue: value) }
         return
      }
      try set(conductedValue: value, for: key)
   }
}
