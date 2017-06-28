//
//  ConductionModel.swift
//  Pods
//
//  Created by Leif Meyer on 5/12/17.
//
//

import Foundation
import Bindable

public protocol ConductionKeyObserver: class {
   // MARK: - Associated Types
   associatedtype Key
   
   typealias KeyChangeBlock = (_ key: Key, _ oldValue: Any?, _ newValue: Any?) -> Void
   
   // MARK: - Public Properties
   var _keyChangeBlocks: [ConductionObserverHandle : KeyChangeBlock] { get set }
   
   // MARK: - Public
   @discardableResult func addKeyObserver(_ changeBlock: @escaping KeyChangeBlock) -> ConductionObserverHandle
   
   func removeKeyObserver(handle: ConductionObserverHandle)
   
   func keyChanged(_ key: Key, oldValue: Any?, newValue: Any?)
}

public extension ConductionKeyObserver {
   @discardableResult public func addKeyObserver(_ changeBlock: @escaping KeyChangeBlock) -> ConductionObserverHandle {
      return _keyChangeBlocks.add(newValue: changeBlock)
   }
   
   public func removeKeyObserver(handle: ConductionObserverHandle) {
      _keyChangeBlocks[handle] = nil
   }
   
   func keyChanged(_ key: Key, oldValue: Any?, newValue: Any?) {
      _keyChangeBlocks.forEach { $0.value(key, oldValue, newValue) }
   }
}

open class ConductionModel<ModelKey: IncKVKeyType, Key: IncKVKeyType, State: ConductionState>: ConductionStateObserver<State>, Bindable, ConductionKeyObserver {
   // MARK: - Nested Types
   public typealias KeyChangeBlock = (_ key: Key, _ oldValue: Any?, _ newValue: Any?) -> Void

   // MARK: - Private Properties
   private var _values: [Key : Any] = [:]
   public var _keyChangeBlocks: [ConductionObserverHandle : KeyChangeBlock] = [:]
   
   // MARK: - Public Propertis
   public var modelData = ConductionData<ModelKey>()
   public var viewData = ConductionData<ModelKey>()
   
   // MARK: - Init
   public override init() {
      super.init()
      modelData.delegate = self
      viewData.delegate = self
   }
   
   public convenience init(model: StringBindable) {
      self.init()
      try! bind(model: model)
   }
   
   public convenience init(modelBindings: [Binding]) {
      self.init()
      try! bind(modelBindings: modelBindings)
   }
   
   // MARK: - Model Binding
   public func bind(model: StringBindable) throws {
      let modelBindings = ModelKey.all.map { return Binding(key: $0, target: model, targetKey: $0) }
      try bind(modelBindings: modelBindings)
   }
   
   public func bind(modelBindings: [Binding]) throws {
      try modelBindings.forEach { try modelData.bind($0) }
   }
   
   public func unbind(model: StringBindable) {
      let modelBindings = ModelKey.all.map { return Binding(key: $0, target: model, targetKey: $0) }
      unbind(modelBindings: modelBindings)
   }
   
   public func unbind(modelBindings: [Binding]) {
      modelBindings.forEach { modelData.unbind($0) }
   }
   
   // MARK: - Subclass Hooks
   open func conductedValue(_ value: Any?, for key: Key) -> Any? { return value }
   open func set(conductedValue value: Any?, for key: Key) throws -> Any? { return value }
   open func willSet(conductedValue value: Any?, for key: Key) {}
   open func didSet(conductedValue: Any?, with value: inout Any?, for key: Key) {}
   
   open func conductViewValue(from modelValue: inout Any?, for key: ModelKey) -> Any? { return value }
   open func didConductViewValue(from modelValue: Any?, for key: ModelKey) {}
   
   open func conductModelValue(from viewValue: inout Any?, for key: ModelKey) -> Any? { return value }
   open func didConductModelValue(from viewValue: Any?, for key: ModelKey) {}
   
   // MARK: - Bindable Protocol
   public static var bindableKeys: [Key] { return Key.all }
   public var bindingBlocks: [Key : [((targetObject: AnyObject, rawTargetKey: String)?, Any?) throws -> Bool?]] = [:]
   public var keysBeingSet: [Key] = []
   
   public func value(for key: Key) -> Any? {
      let value = _values[key]
      return conductedValue(value, for: key)
   }
   
   public func setOwn(value: inout Any?, for key: Key) throws {
      let oldValue = _values[key]
      willSet(conductedValue: value, for: key)
      let conductedValue = try set(conductedValue: value, for: key)
      _values[key] = conductedValue
      didSet(conductedValue: conductedValue, with: &value, for: key)
      keyChanged(key, oldValue: oldValue, newValue: conductedValue)
   }
}

extension ConductionModel: ConductionDataDelegate {
   func conductionData<DataKey>(_ conductionData: ConductionData<DataKey>, willSetValue value: inout Any?, for key: DataKey) {
      guard let key = key as? ModelKey else { fatalError() }
      if conductionData === modelData {
         viewData[key] = conductViewValue(from: &value, for: key)
         didConductViewValue(from: value, for: key)
      } else if conductionData === viewData {
         modelData[key] = conductModelValue(from: &value, for: key)
         didConductModelValue(from: value, for: key)
      } else {
         fatalError()
      }
   }
}

public protocol StringKeyedConductionModelType: StringBindable {
   // MARK: – Keys
   var modelReadKeyStrings: [String] { get }
   var modelWriteKeyStrings: [String] { get }
   var viewReadKeyStrings: [String] { get }
   var viewWriteKeyStrings: [String] { get }
}

public extension StringKeyedConductionModelType {
   // MARK: - Keys
   var modelKeyStrings: [String] { return modelReadKeyStrings + modelWriteKeyStrings }
   var viewKeyStrings: [String] { return modelReadKeyStrings + modelWriteKeyStrings }
}

public protocol KeyedConductionModelType: Bindable, StringKeyedConductionModelType {
   // MARK: – Keys
   var modelReadKeys: [Key] { get }
   var modelWriteKeys: [Key] { get }
   var viewReadKeys: [Key] { get }
   var viewWriteKeys: [Key] { get }
}

public extension KeyedConductionModelType {
   // MARK: - Keys
   var modelKeys: [Key] { return modelReadKeys + modelWriteKeys }
   var viewKeys: [Key] { return viewReadKeys + viewWriteKeys }

   // MARK: - StringKeyedConductionModelType Protocol
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

open class KeyedConductionModel<Key: IncKVKeyType, State: ConductionState>: ConductionStateObserver<State>, KeyedConductionModelType {
   // MARK: Private Properties
   private var values: [Key : Any] = [:]
   
   // MARK: Public Properties
   open var modelReadOnlyKeys: [Key] { return [] }
   open var modelReadWriteKeys: [Key] { return [] }
   open var modelWriteOnlyKeys: [Key] { return [] }
   open var viewReadOnlyKeys: [Key] { return [] }
   open var viewReadWriteKeys: [Key] { return [] }
   open var viewWriteOnlyKeys: [Key] { return [] }
   
   // MARK: - Init
   public override init() {
      super.init()
   }
   
   public init?(model: StringBindable) {
      super.init()
      do {
         try bind(model: model)
      } catch {
         return nil
      }
   }

   public init?(modelBindings: [Binding]) {
      super.init()
      do {
         try bind(modelBindings: modelBindings)
      } catch {
         return nil
      }
   }

   public init?<T: IncKVStringCompliance>(sync model: inout T) {
      super.init()
      do {
         try sync(model: &model)
      } catch {
         return nil
      }
   }
   
   public init?(syncBindings: [Binding]) {
      super.init()
      do {
         try sync(modelBindings: syncBindings)
      } catch {
         return nil
      }
   }

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
   open func didSet(conductedValue: Any?, with value: inout Any?, for key: Key) {}
   
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
   
   public func setOwn(value: inout Any?, for key: Key) throws {
      guard viewKeys.contains(key) || modelReadKeys.contains(key) else { fatalError() }
      willSet(conductedValue: value, for: key)
      let conductedValue = try set(conductedValue: value, for: key)
      values[key] = conductedValue
      didSet(conductedValue: conductedValue, with: &value, for: key)
   }
}

open class ReadWriteConductionModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State> {
   open override var modelReadWriteKeys: [Key] { return Key.all }
   open override var viewReadWriteKeys: [Key] { return Key.all }
}

open class ReadOnlyConductionModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State> {
   open override var modelReadOnlyKeys: [Key] { return Key.all }
   open override var viewReadOnlyKeys: [Key] { return Key.all }
}

open class WriteOnlyConductionModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State> {
   open override var modelWriteOnlyKeys: [Key] { return Key.all }
   open override var viewWriteOnlyKeys: [Key] { return Key.all }
}

protocol ConductionDataDelegate: class {
   func conductionData<DataKey>(_ conductionData: ConductionData<DataKey>, willSetValue value: inout Any?, for key: DataKey)
}

public class ConductionData<Key: IncKVKeyType>: Bindable, ConductionKeyObserver {
   // MARK: - Nested Types
   public typealias KeyChangeBlock = (_ key: Key, _ oldValue: Any?, _ newValue: Any?) -> Void
   
   // MARK: - Private Properties
   private var _values: [Key : Any] = [:]
   public var _keyChangeBlocks: [ConductionObserverHandle : KeyChangeBlock] = [:]
   
   // MARK: - Public Properties
   weak var delegate: ConductionDataDelegate?
   
   // MARK: - Bindable
   public var bindingBlocks: [Key : [((targetObject: AnyObject, rawTargetKey: String)?, Any?) throws -> Bool?]] = [:]
   public var keysBeingSet: [Key] = []
   
   public func value(for key: Key) -> Any? {
      return _values[key]
   }
   
   public func setOwn(value: inout Any?, for key: Key) throws {
      let oldValue = _values[key]
      delegate?.conductionData(self, willSetValue: &value, for: key)
      _values[key] = value
      keyChanged(key, oldValue: oldValue, newValue: value)
   }
}
