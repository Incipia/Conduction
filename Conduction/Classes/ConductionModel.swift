//
//  ConductionModel.swift
//  Pods
//
//  Created by Leif Meyer on 5/12/17.
//
//

import Foundation
import Bindable

public protocol ConductionKeyObserverType: class {
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

public extension ConductionKeyObserverType {
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

open class ConductionModel<ModelKey: IncKVKeyType, Key: IncKVKeyType, State: ConductionState>: ConductionStateObserver<State>, Bindable, ConductionKeyObserverType {
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
      let oldValue = self[key]
      willSet(conductedValue: value, for: key)
      let conductedValue = try set(conductedValue: value, for: key)
      _values[key] = conductedValue
      didSet(conductedValue: conductedValue, with: &value, for: key)
      keyChanged(key, oldValue: oldValue, newValue: self[key])
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

open class KeyedConductionModel<Key: IncKVKeyType, State: ConductionState>: ConductionStateObserver<State>, KeyedConductionModelType, ConductionKeyObserverType {
   // MARK: - Nested Types
   public typealias KeyChangeBlock = (_ key: Key, _ oldValue: Any?, _ newValue: Any?) -> Void
   
   // MARK: Private Properties
   private var _values: [Key : Any] = [:]
   public var _keyChangeBlocks: [ConductionObserverHandle : KeyChangeBlock] = [:]
   
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
   public func resetKeys(_ keys: [Key]? = nil) {
      let keys = keys ?? Key.all
      keys.forEach { self[$0] = nil }
   }
   
   public func resetAll() {
      resetKeys()
      _values.removeAll()
      resetState()
   }
   
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
         try modelBindings.filter(key: $0).forEach { try $0.set(targetValue: self.value(for: $0.targetKey)) }
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
      let value = _values[key]
      return conductedValue(value, for: key)
   }
   
   public func setOwn(value: inout Any?, for key: Key) throws {
      let oldValue = self[key]
      willSet(conductedValue: value, for: key)
      let conductedValue = try set(conductedValue: value, for: key)
      _values[key] = conductedValue
      didSet(conductedValue: conductedValue, with: &value, for: key)
      keyChanged(key, oldValue: oldValue, newValue: self[key])
   }
}

open class ReadWriteKeyedConductionModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State> {
   open override var modelReadWriteKeys: [Key] { return Key.all }
   open override var viewReadWriteKeys: [Key] { return Key.all }
}

open class ReadOnlyKeyedConductionModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State> {
   open override var modelReadOnlyKeys: [Key] { return Key.all }
   open override var viewReadOnlyKeys: [Key] { return Key.all }
}

open class WriteOnlyKeyedConductionModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State> {
   open override var modelWriteOnlyKeys: [Key] { return Key.all }
   open override var viewWriteOnlyKeys: [Key] { return Key.all }
}

public protocol ConductionSyncModelDelegate: class {
   func saveKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ savedKeys: [Model.Key]) -> Void)?)
   func loadKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ loadedKeys: [Model.Key]) -> Void)?)
   func cancelSavingKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ cancelledKeys: [Model.Key]) -> Void)?)
   func cancelLoadingKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ cancelledKeys: [Model.Key]) -> Void)?)
}

public extension ConductionSyncModelDelegate {
   func saveKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ savedKeys: [Model.Key]) -> Void)?) {
      completion?([])
   }
   func loadKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ loadedKeys: [Model.Key]) -> Void)?) {
      completion?([])
   }
   func cancelSavingKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ cancelledKeys: [Model.Key]) -> Void)?) {
      completion?([])
   }
   func cancelLoadingKeys<Model: ConductionSyncModelType>(_ keys: [Model.Key], forModel model: Model, completion: ((_ cancelledKeys: [Model.Key]) -> Void)?) {
      completion?([])
   }
}

public protocol ConductionSyncModelType: KeyedConductionModelType {
   var dirtyKeys: [Key] { get }
}

open class ConductionSyncModel<Key: IncKVKeyType, State: ConductionState>: KeyedConductionModel<Key, State>, ConductionSyncModelType {
   // MARK: - Private Properties
   private var _saveTimer: Timer?
   private var _loadTimer: Timer?
   
   // MARK: - Public Properties
   public private(set) var savingKeys: [Key] = []
   public private(set) var loadingKeys: [Key] = []
   public private(set) var cancellingSavingKeys: [Key] = []
   public private(set) var cancellingLoadingKeys: [Key] = []
   public var busyKeys: [Key] { return savingKeys + loadingKeys }
   open var dirtyKeys: [Key] { return Key.all.filter { self.keyIsDirty($0) } }
   public weak var syncDelegate: ConductionSyncModelDelegate? {
      didSet {
         setSaveTimer()
         setLoadTimer()
      }
   }
   
   // MARK: - Subclass Hooks
   open func keyIsDirty(_ key: Key) -> Bool {
      return false
   }
   
   open func cleanKey(_ key: Key) {}
   
   open func saveInterval(key: Key, setInterval: TimeInterval?) -> TimeInterval? { return nil }
   
   open func loadInterval(key: Key, setInterval: TimeInterval?) -> TimeInterval? { return nil }
   
   open func willSave(keys: inout [Key]) {}
   
   open func didSave(keys: [Key], attemptedKeys: [Key]) {}

   open func willLoad(keys: inout [Key]) {}

   open func didLoad(keys: [Key], attemptedKeys: [Key]) {}
   
   open func willCancelSaving(keys: inout [Key]) {}
   
   open func didCancelSaving(keys: [Key], attemptedKeys: [Key]) {}

   open func willCancelLoading(keys: inout [Key]) {}
   
   open func didCancelLoading(_ keys: [Key], attemptedKeys: [Key]) {}
   
   // MARK: - Public
   @objc public func save() { saveKeys(dirtyKeys) }
   
   public func saveKeys(_ keys: [Key]) {
      var keys = keys.filter { dirtyKeys.contains($0) && !busyKeys.contains($0) }
      guard !keys.isEmpty else { return }
      willSave(keys: &keys)
      guard let syncDelegate = syncDelegate, !keys.isEmpty else {
         didSave(keys: [], attemptedKeys: keys)
         return
      }
      savingKeys.append(contentsOf: keys)
      syncDelegate.saveKeys(keys, forModel: self) { [weak self] savedKeys in
         guard let strongSelf = self else { return }
         strongSelf.savingKeys = []
         strongSelf.didSave(keys: savedKeys, attemptedKeys: keys)
         strongSelf.setSaveTimer()
      }
      setSaveTimer()
   }
   
   @objc public func cancelSaving() { cancelSavingKeys(savingKeys) }
   
   public func cancelSavingKeys(_ keys: [Key]) {
      var keys = keys.filter { self.savingKeys.contains($0) && !self.cancellingSavingKeys.contains($0) }
      guard !keys.isEmpty else { return }
      willCancelSaving(keys: &keys)
      guard let syncDelegate = syncDelegate, !keys.isEmpty else {
         didCancelSaving(keys: [], attemptedKeys: keys)
         return
      }
      syncDelegate.cancelSavingKeys(keys, forModel: self) { [weak self] cancelledKeys in
         guard let strongSelf = self else { return }
         strongSelf.savingKeys = strongSelf.savingKeys.filter { !cancelledKeys.contains($0) }
         strongSelf.cancellingSavingKeys = []
         strongSelf.didCancelSaving(keys: cancelledKeys, attemptedKeys: keys)
         strongSelf.setSaveTimer()
      }
   }
   
   @objc public func setSaveTimer() {
      var interval: TimeInterval? = nil
      let setInterval: TimeInterval? = _saveTimer?.isValid ?? false ? max(_saveTimer!.fireDate.timeIntervalSinceNow, 0.0) : nil
      
      defer {
         if interval != setInterval {
            if let saveTimer = _saveTimer, saveTimer.isValid {
               saveTimer.invalidate()
            }
            if let interval = interval {
               _saveTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(ConductionSyncModel.save), userInfo: nil, repeats: false)
            } else {
               _saveTimer = nil
            }
         }
      }
      
      guard let syncDelegate = syncDelegate else { return }
      
      interval = Set(dirtyKeys).subtracting(Set(busyKeys)).flatMap { return saveInterval(key: $0, setInterval: setInterval) }.min()
   }

   public func load() {
      fatalError()
   }
   
   public func setLoadTimer() {
      print("set load timer not yet implemented")
   }
   
   // MARK: - Overridden
   public override func setOwn(value: inout Any?, for key: Key) throws {
      try super.setOwn(value: &value, for: key)
      setSaveTimer()
      setLoadTimer()
   }
}

protocol ConductionDataDelegate: class {
   func conductionData<DataKey>(_ conductionData: ConductionData<DataKey>, willSetValue value: inout Any?, for key: DataKey)
}

public class ConductionData<Key: IncKVKeyType>: Bindable, ConductionKeyObserverType {
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
      let oldValue = self[key]
      delegate?.conductionData(self, willSetValue: &value, for: key)
      _values[key] = value
      keyChanged(key, oldValue: oldValue, newValue: self[key])
   }
}
