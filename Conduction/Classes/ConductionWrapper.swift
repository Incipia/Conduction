//
//  ConductionWrapper.swift
//  Bindable
//
//  Created by Gregory Klein on 6/28/17.
//

import Foundation

open class StaticConductionWrapper<DataModel> {
   // MARK: - Public Properties
   public let model: DataModel
   
   // MARK: - Init
   public init(model: DataModel) {
      self.model = model
   }
}

public protocol ConductionWrapperObserverType: class {
   // MARK: - Associated Types
   associatedtype DataModel
   
   typealias ModelChangeBlock = (_ old: DataModel, _ new: DataModel) -> Void
   
   // MARK: - Public Properties
   var model: DataModel! { get }
   var _modelChangeBlocks: [ConductionObserverHandle : ModelChangeBlock] { get set }
   
   // MARK: - Public
   @discardableResult func addModelObserver(_ changeBlock: @escaping ModelChangeBlock) -> ConductionObserverHandle
   
   func removeModelObserver(handle: ConductionObserverHandle)
   
   func modelChanged(oldModel: DataModel?)
}

public extension ConductionWrapperObserverType {
   @discardableResult public func addModelObserver(_ changeBlock: @escaping ModelChangeBlock) -> ConductionObserverHandle {
      if let model = model {
         changeBlock(model, model)
      }
      return _modelChangeBlocks.add(newValue: changeBlock)
   }

   public func removeModelObserver(handle: ConductionObserverHandle) {
      _modelChangeBlocks[handle] = nil
   }
   
   public func modelChanged(oldModel: DataModel? = nil) {
      guard oldModel != nil || model != nil else { return }
      _modelChangeBlocks.forEach { $0.value(oldModel ?? model, model ?? oldModel!) }
   }
}

open class StatelessConductionWrapper<DataModel>: ConductionWrapperObserverType {
   // MARK: - Nested Types
   public typealias ModelChangeBlock = (_ old: DataModel, _ new: DataModel) -> Void
   
   // MARK: - Private Properties
   public var _modelChangeBlocks: [ConductionObserverHandle : ModelChangeBlock] = [:]

   // MARK: - Public Properties
   public var model: DataModel! {
      didSet { modelChanged(oldModel: oldValue) }
   }
   
   public var hasModel: Bool { return model != nil }
   
   // MARK: - Init
   public init(model: DataModel?) {
      self.model = model
   }
}

open class ConductionWrapper<DataModel, State: ConductionState>: StatelessConductionWrapper<DataModel>, ConductionStateObserverType {
   // MARK: - Nested Types
   public typealias StateChangeBlock = (_ old: State, _ new: State) -> Void
   
   // MARK: - Private Properties
   public var _stateChangeBlocks: [ConductionObserverHandle : StateChangeBlock] = [:]
   
   // MARK: - Public Properties
   public var state: State = State() {
      didSet { stateChanged(oldState: oldValue) }
   }
}
