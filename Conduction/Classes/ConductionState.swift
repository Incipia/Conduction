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

open class ConductionStateObserver<State: ConductionState> {
   // MARK: - Public Properties
   public var state = State() {
      didSet { stateChanged(oldState: oldValue) }
   }
   
   public var onStateChange: ((State, State) -> Void)? {
      didSet { stateChanged() }
   }
   
   public var onValueChange: (() -> Void)? {
      didSet { valueChanged() }
   }
   
   public var onChange: (() -> Void)? {
      didSet { onChange?() }
   }
   
   // MARK: - Init
   public init() {}
   
   // MARK: - Public
   public func stateChanged(oldState: State? = nil) {
      onStateChange?(oldState ?? state, state)
      onChange?()
   }
   
   public func valueChanged() {
      onValueChange?()
      onChange?()
   }
}
