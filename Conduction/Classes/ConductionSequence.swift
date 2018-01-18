//
//  ConductionSequence.swift
//  Bindable
//
//  Created by Leif Meyer on 1/16/18.
//

import Foundation

public protocol ConductionStepState: ConductionState {
   associatedtype Step: Equatable
   
   var step: Step? { get set }
}

public struct ConductionSequenceLayer<Step: Equatable> {
   // MARK: - Public Properties
   let step: Step
   let conductor: Conductor?
}

public class ConductionSequence<State: ConductionStepState>: ConductionStateObserver<State>, ConductionContext {
   // MARK: - Private Properties
   private var _oldStateContext: Any?
   
   // MARK: - Public Properties
   public var context: Any? { return state }
   public var contextuals: [ConductionContextual] { return layers.flatMap { $0.conductor as? ConductionContextual } }
   public let navigationContext: UINavigationController
   public private(set) var layers: [ConductionSequenceLayer<State.Step>] = []

   // MARK: - Init
   public init(navigationContext: UINavigationController) {
      self.navigationContext = navigationContext
      
      super.init()
   }

   // MARK: - Subclass Hooks
   open func didContextChangeWithState(oldContext: Any?, oldState: State?) -> Bool { return true }
   open func conductor(step: State.Step) -> Conductor? { return nil }

   // MARK: - Public
   public func set(step: State.Step?) { state.step = step }
   
   public func addStateLayers(steps: [State.Step], atIndex index: Int, animated: Bool) {
      guard !steps.isEmpty else { return }
      layers.insert(contentsOf: steps.map { ConductionSequenceLayer<State.Step>(step: $0, conductor: conductor(step: $0)) }, at: index)
      if state.step != layers.last?.step {
         state.step = layers.last?.step
      }
      layers[index..<index+steps.count].forEach {
         if let contextualConductor = $0.conductor as? ConductionContextual {
            added(contextual: contextualConductor)
         }
         $0.conductor?.show(with: navigationContext, animated: animated)
      }
   }
   
   public func removeLayers(inRange range: Range<Int>) {
      var newLayers = layers
      newLayers.removeSubrange(range)
      if state.step != newLayers.last?.step {
         state.step = layers.last?.step
      }
      let removedContext = context
      layers[range].reversed().forEach {
         if let removedContext = removedContext, let contextualConductor = $0.conductor as? ConductionContextual {
            $0.conductor?.dismissWithCompletion {
               contextualConductor.leave(context: removedContext)
            }
         } else {
            $0.conductor?.dismiss()
         }
         layers = newLayers
      }
   }
   
   // MARK: - Overridden
   public override func stateWillChange(nextState: State) {
      _oldStateContext = context
   }
   
   public func stateChanged(oldState: State? = nil) {
      defer {
         _stateChangeBlocks.forEach { $0.value(oldState ?? state, state) }
      }

      let oldContext = _oldStateContext
      _oldStateContext = nil
      if didContextChangeWithState(oldContext: oldContext, oldState: oldState) {
         contextChanged(oldContext: oldContext)
      }
      
      guard layers.last?.step != state.step else { return }
      guard let step = state.step else {
         removeLayers(inRange: 0..<layers.count)
         return
      }
      guard let reversedIndex = (layers.reversed().map { $0.step }.index(of: step)) else {
         addStateLayers(steps: [step], atIndex: layers.count, animated: true)
         return
      }
      let index = layers.count - reversedIndex - 1
      if index + 1 < layers.count {
         removeLayers(inRange: index+1..<layers.count)
      }
   }
}

