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
}

public extension ConductionModelType {
   // MARK: - Keys
   var modelKeys: [Key] { return modelReadKeys + modelWriteKeys }
   var viewKeys: [Key] { return modelReadKeys + modelWriteKeys }

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

open class ConductionStateModel<State: ConductionModelState> {
   // MARK: Public Properties
   public var state: State = State() {
      didSet {
         onStateChange?(state)
      }
   }
   public var onStateChange: ((State) -> Void)? {
      didSet {
         onStateChange?(state)
      }
   }
   
   // MARK: - Init
   public init() {}
}

open class ConductionModel<Key: IncKVKeyType, State: ConductionModelState>: ConductionStateModel<State>, ConductionModelType {
   // MARK: Private Properties
   private var values: [Key : Any] = [:]
   
   // MARK: Public Properties
   open var modelReadOnlyKeys: [Key] { return [] }
   open var modelReadWriteKeys: [Key] { return Key.all }
   open var modelWriteOnlyKeys: [Key] { return [] }
   open var viewReadOnlyKeys: [Key] { return [] }
   open var viewReadWriteKeys: [Key] { return Key.all }
   open var viewWriteOnlyKeys: [Key] { return [] }
   
   // MARK: - Public
   public func value<T>(for key: Key, default defaultValue: T?) -> T? {
      return value(for: key) as? T ?? defaultValue
   }
   
   // MARK: - Model Binding
   public func bind(model: StringBindable) throws {
      let modelBindings = modelKeys.map { return Binding(key: $0, target: model, targetKey: $0) }
      try bind(modelBindings: modelBindings)
   }
   
   public func bind(modelBindings: [Binding]) throws {
      try modelReadOnlyKeys.forEach {
         try modelBindings.filter(key: $0).forEach { try $0.target.bindOneWay(key: $0.targetKey, to: self, key: $0.key) }
      }
      try modelReadWriteKeys.forEach {
         try modelBindings.filter(key: $0).forEach { try self.bind($0) }
      }
      try modelWriteOnlyKeys.forEach {
         try modelBindings.filter(key: $0).forEach { try self.bindOneWay(key: $0.key, to: $0.target, key: $0.targetKey) }
      }
   }

   public func unbind(model: StringBindable) {
      let modelBindings = modelKeys.map { return Binding(key: $0, target: model, targetKey: $0) }
      unbind(modelBindings: modelBindings)
   }
   
   public func unbind(modelBindings: [Binding]) {
      modelReadOnlyKeys.forEach {
         modelBindings.filter(key: $0).forEach { $0.target.unbindOneWay(key: $0.targetKey, to: self, key: $0.key) }
      }
      modelReadWriteKeys.forEach {
         modelBindings.filter(key: $0).forEach { self.unbind($0) }
      }
      modelWriteOnlyKeys.forEach {
         modelBindings.filter(key: $0).forEach { self.unbindOneWay(key: $0.key, to: $0.target, key: $0.targetKey) }
      }
   }
   
   // MARK: - Model Syncing
   public func sync<T: IncKVStringCompliance>(model: inout T) throws {
      try modelReadKeys.forEach {
         try self.set(value: model.value(for: $0.rawValue), for: $0)
      }
      try modelWriteOnlyKeys.forEach {
         try model.set(value: self.value(for: $0), for: $0.rawValue)
      }
   }
   
   public func sync(modelBindings: [Binding]) throws {
      try modelReadKeys.forEach {
         try modelBindings.filter(key: $0).forEach { try self.set(value: $0.targetValue, for: $0.key) }
      }
      try modelWriteOnlyKeys.forEach {
         try modelBindings.filter(key: $0).forEach { try $0.set(targetValue: self.value(for: $0.key)) }
      }
   }

   // MARK: - Subclass Hooks
   open func conductedValue(_ value: Any?, for key: Key) -> Any? { return value }
   open func set(conductedValue value: Any?, for key: Key) throws -> Any? { return value }
   open func willSet(conductedValue value: Any?, for key: Key) {}
   open func didSet(conductedValue value: Any?, for key: Key) {}
   
   // MARK: - ConductionModelType Protocol
   open var modelReadKeys: [Key] { return modelReadOnlyKeys + modelReadWriteKeys }
   open var modelWriteKeys: [Key] { return modelReadWriteKeys + modelWriteOnlyKeys }
   open var viewReadKeys: [Key] { return viewReadOnlyKeys + viewReadWriteKeys }
   open var viewWriteKeys: [Key] { return viewReadWriteKeys + viewWriteOnlyKeys }
   
   // MARK: - Bindable Protocol
   public static var bindableKeys: [Key] { return Key.all }
   public var bindingBlocks: [Key : [((targetObject: AnyObject, rawTargetKey: String)?, Any?) throws -> Bool?]] = [:]
   public var keysBeingSet: [Key] = []
   
   public func value(for key: Key) -> Any? {
      guard viewReadKeys.contains(key) || modelKeys.contains(key) else { fatalError() }
      let value = values[key]
      return conductedValue(value, for: key)
   }
   
   public func setOwn(value: Any?, for key: Key) throws {
      guard viewKeys.contains(key) || modelReadKeys.contains(key) else { fatalError() }
      willSet(conductedValue: value, for: key)
      let conductedValue = try set(conductedValue: value, for: key)
      values[key] = conductedValue
      didSet(conductedValue: value, for: key)
   }
}
