//
//  ConductionContext.swift
//  Bindable
//
//  Created by Leif Meyer on 1/17/18.
//

import Foundation

public protocol ConductionContext {
   var context: Any? { get }
   var contextuals: [ConductionContextual] { get }
   
   func added(contextual: ConductionContextual)
   func removed(contextual: ConductionContextual)
   func contextChanged(oldContext: Any?)
}

public extension ConductionContext {
   func added(contextual: ConductionContextual) {
      guard let context = context else { return }
      contextual.enter(context: context)
   }
   
   func removed(contextual: ConductionContextual) {
      guard let context = context else { return }
      contextual.leave(context: context)
   }
   
   func contextChanged(oldContext: Any?) {
      switch oldContext {
      case .some(let someOldContext):
         switch context {
         case .some(let someContext): contextuals.forEach { $0.changeContext(from: someOldContext, to: someContext) }
         case .none: contextuals.forEach { $0.leave(context: someOldContext) }
         }
      case .none:
         switch context {
         case .some(let someContext): contextuals.forEach { $0.enter(context: someContext) }
         case .none: break
         }
      }
   }
}

public protocol ConductionContextual {
   func enter(context: Any)
   func leave(context: Any)
   func changeContext(from oldContext: Any, to context: Any)
}

public extension ConductionContextual {
   func enter(context: Any) {}
   func leave(context: Any) {}
   func changeContext(from oldContext: Any, to context: Any) {
      leave(context: oldContext)
      enter(context: context)
   }
}
