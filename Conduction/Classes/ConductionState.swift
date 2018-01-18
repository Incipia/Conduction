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

public protocol ConductionStateObserverType: class {
   // MARK: - Associated Types
   associatedtype State: ConductionState
   
   typealias StateChangeBlock = (_ old: State, _ new: State) -> Void
   
   // MARK: - Public Properties
   var state: State { get }
   var _stateChangeBlocks: [ConductionObserverHandle : StateChangeBlock] { get set }
   
   // MARK: - Public
   @discardableResult func addStateObserver(_ changeBlock: @escaping StateChangeBlock) -> ConductionObserverHandle
   
   func removeStateObserver(handle: ConductionObserverHandle)
   
   func stateChanged(oldState: State?)
}

public extension ConductionStateObserverType {
   @discardableResult public func addStateObserver(_ changeBlock: @escaping StateChangeBlock) -> ConductionObserverHandle {
      changeBlock(state, state)
      return _stateChangeBlocks.add(newValue: changeBlock)
   }
   
   public func removeStateObserver(handle: ConductionObserverHandle) {
      _stateChangeBlocks[handle] = nil
   }
   
   public func stateChanged(oldState: State? = nil) {
      _stateChangeBlocks.forEach { $0.value(oldState ?? state, state) }
   }
}

open class ConductionStateObserver<State: ConductionState>: ConductionStateObserverType {
   // MARK: - Nested Types
   public typealias StateChangeBlock = (_ old: State, _ new: State) -> Void
   
   // MARK: - Private Properties
   public var _stateChangeBlocks: [ConductionObserverHandle : StateChangeBlock] = [:]
   
   // MARK: - Public Properties
   public var state: State = State() {
      willSet { stateWillChange(nextState: newValue) }
      didSet { stateChanged(oldState: oldValue) }
   }
   
   // MARK: - Init
   public init() {}
   
   // MARK: - Subclass Hooks
   open func stateWillChange(nextState: State) {}
   open func stateChanged(oldState: State? = nil) {
      _stateChangeBlocks.forEach { $0.value(oldState ?? state, state) }
   }

   // MARK: - Public
   public func resetState() {
      state = State()
   }
}

protocol ConductionObserverHandleType {
   // MARK: - Public Properties
   static var first: Self { get }
   var next: Self { get }
}

extension ConductionObserverHandle: ConductionObserverHandleType {
   static var first: ConductionObserverHandle { return 0 }
   var next: ConductionObserverHandle { return self + 1 }
}

extension Dictionary where Key: ConductionObserverHandleType {
   // MARK: - Public Properties
   var nextHandle: Key {
      var handle = Key.first
      while self.keys.contains(handle) {
         handle = handle.next
      }

      return handle
   }
   
   // MARK: - Public
   mutating func add(newValue: Value) -> Key {
      let newKey = nextHandle
      self[newKey] = newValue
      
      return newKey
   }
}
