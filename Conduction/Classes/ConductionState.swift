//
//  ConductionState.swift
//  Bindable
//
//  Created by Gregory Klein on 6/28/17.
//

import Foundation

public protocol ConductionState {
   init()
   mutating func update(_ block: (inout Self) -> Void)
}

extension ConductionState {
   mutating public func update(_ block: (inout Self) -> Void) {
      block(&self)
   }
}

public struct EmptyConductionState: ConductionState {
   public init() {}
}

public typealias ConductionObserverHandle = UInt

open class ConductionStateObserver<State: ConductionState> {
   // MARK: - Nested Types
   public typealias ChangeBlock = (_ old: State, _ new: State) -> Void
   
   // MARK: - Private Properties
   private var _changeBlocks: [ConductionObserverHandle : ChangeBlock] = [:]
   
   // MARK: - Public Properties
   public var state = State() {
      didSet { stateChanged(oldState: oldValue) }
   }
   
   // MARK: - Init
   public init() {}
   
   // MARK: - Public
   @discardableResult public func addStateObserver(_ changeBlock: @escaping ChangeBlock) -> ConductionObserverHandle {
      var handle: ConductionObserverHandle = 0
      while _changeBlocks.keys.contains(handle) {
         handle += 1
      }
      
      _changeBlocks[handle] = changeBlock
      
      return handle
   }
   
   public func removeStateObserver(handle: ConductionObserverHandle) {
      _changeBlocks[handle] = nil
   }
   
   public func stateChanged(oldState: State? = nil) {
      _changeBlocks.forEach { $0.value(oldState ?? state, state) }
   }
}
