//
//  ConductionResource.swift
//  Bindable
//
//  Created by Leif Meyer on 11/16/17.
//

import Foundation

public enum ConductionResourceState<Input, Resource> {
   case empty
   case fetching(id: ConductionResourceFetchID, priority: Int?)
   case processing(id: ConductionResourceFetchID, priority: Int?, input: Input?)
   case fetched(Resource?)
   case invalid(Resource?)
}

public typealias ConductionResourceObserver = UUID

public typealias ConductionResourceFetchID = UUID

public typealias ConductionResourceFetchBlock<Input, Resource> = (_ state: ConductionResourceState<Input, Resource>, _ completion: @escaping (_ fetchedInput: Input?) -> Void) -> Void

public typealias ConductionResourceTransformBlock<Input, Resource> = (_ state: ConductionResourceState<Input, Resource>, _ completion: @escaping (_ resource: Resource?) -> Void) -> Void

public typealias ConductionResourceCommitBlock<Input, Resource> = (_ state: ConductionResourceState<Input, Resource>, _ nextState: ConductionResourceState<Input, Resource>, _ input: Input?) -> ConductionResourceState<Input, Resource>?

public typealias ConductionResourceObserverBlock<Resource> = (_ resource: Resource?) -> Void

fileprivate typealias ConductionResourceObserverEntry<Resource> = (id: ConductionResourceObserver, priority: Int, block: ConductionResourceObserverBlock<Resource>)

open class ConductionBaseResource<Input, Resource> {
   // MARK: - Private Properties
   private var _getBlocks: [ConductionResourceObserverEntry<Resource>] = []
   private var _observerBlocks: [ConductionResourceObserverEntry<Resource>] = []
   private var _stateObserverBlocks: [(id: ConductionResourceObserver, priority: Int, block: (_ oldState: ConductionResourceState<Input, Resource>, _ newState: ConductionResourceState<Input, Resource>) -> Void)] = []
   private var _getHistory: [ConductionResourceObserver] = []
   
   // MARK: - Public Properties
   public private(set) var state: ConductionResourceState<Input, Resource> = .empty {
      didSet {
         _stateObserverBlocks.sorted { $0.priority > $1.priority }.forEach { $0.block(oldValue, state) }
      }
   }
   public let dispatchQueue: DispatchQueue
   public let defaultPriority: Int
   public let fetchBlock: ConductionResourceFetchBlock<Input, Resource>?
   public let transformBlock: ConductionResourceTransformBlock<Input, Resource>?
   public let commitBlock: ConductionResourceCommitBlock<Input, Resource>
   
   // MARK: - Init
   public init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0, fetchBlock: ConductionResourceFetchBlock<Input, Resource>? = nil, transformBlock: ConductionResourceTransformBlock<Input, Resource>? = nil, commitBlock: @escaping ConductionResourceCommitBlock<Input, Resource> = { _, nextState, _ in return nextState }) {
      self.dispatchQueue = dispatchQueue
      self.defaultPriority = defaultPriority
      self.fetchBlock = fetchBlock
      self.transformBlock = transformBlock
      self.commitBlock = commitBlock
   }
   
   // MARK: - Public
   @discardableResult public func get(observer: ConductionResourceObserver? = nil, priority: Int? = nil, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatchQueue.async {
         self._get(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }

   @discardableResult public func observe(observer: ConductionResourceObserver? = nil, priority: Int? = nil, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatchQueue.async {
         self._observe(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }

   @discardableResult public func observeState(observer: ConductionResourceObserver? = nil, priority: Int? = nil, completion: @escaping (_ oldState: ConductionResourceState<Input, Resource>, _ newState: ConductionResourceState<Input, Resource>) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatchQueue.async {
         self._observeState(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }

   public func forget(_ observer: ConductionResourceObserver) {
      dispatchQueue.async {
         self._forget(observer)
      }
   }
   
   public func forgetAll() {
      dispatchQueue.async {
         self._forgetAll()
      }
   }
   
   public func check(completion: @escaping (_ state: ConductionResourceState<Input, Resource>) -> Void) {
      dispatchQueue.async {
         self._check(completion: completion)
      }
   }

   public func expire() {
      dispatchQueue.async {
         self._expire()
      }
   }
   
   public func invalidate() {
      dispatchQueue.async {
         self._invalidate()
      }
   }
   
   public func setInput( _ input: Input?) {
      dispatchQueue.async {
         self._setInput(input)
      }
   }
   
   public func setResource(_ resource: Resource?) {
      dispatchQueue.async {
         self._setResource(resource)
      }
   }
   
   // MARK: - Private
   private func _transition(newState: ConductionResourceState<Input, Resource>, input: Input? = nil) {
      let oldState = state
      guard let nextState = commitBlock(oldState, newState, input) else { return }
      state = nextState
      switch state {
      case .invalid(let resource):
         _callWaitingBlocks(resource: resource)
         forgetAll()
      case .empty: break
      case .fetching(let id, _):
         switch oldState {
         case .fetching(let oldID, _): guard id != oldID else { return }
         default: break
         }
         _fetch(id: id)
      case .processing(let id, _, let input):
         switch oldState {
         case .processing(let oldID, _, _): guard id != oldID else { return }
         default: break
         }
         _process(id: id, input: input)
      case .fetched(let resource): _callWaitingBlocks(resource: resource)
      }
   }
   
   private func _get(observer: ConductionResourceObserver?, priority: Int?, completion: @escaping (_ resource: Resource?) -> Void) {
      let observer = observer ?? ConductionResourceObserver()
      guard !_getHistory.contains(observer) else { return }
      
      switch state {
      case .invalid: return
      case .fetched(let resource):
         completion(resource)
         return
      default:
         let oldPriority = _priority()
         _getBlocks = _getBlocks.filter { $0.id != observer }
         _getBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         switch state {
         case .empty: _transition(newState: .fetching(id: ConductionResourceFetchID(), priority: _priority()))
         case .fetching, .processing: _updatePriority(oldPriority: oldPriority)
         default: break
         }
      }
   }
   
   private func _observe(observer: ConductionResourceObserver?, priority: Int?, completion: @escaping (_ resource: Resource?) -> Void) {
      switch state {
      case .invalid: return
      default:
         let oldPriority = _priority()
         let observer = observer ?? ConductionResourceObserver()
         _observerBlocks = _observerBlocks.filter { $0.id != observer }
         _observerBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         _updatePriority(oldPriority: oldPriority)
      }
   }

   private func _observeState(observer: ConductionResourceObserver?, priority: Int?, completion: @escaping (_ oldState: ConductionResourceState<Input, Resource>, _ newState: ConductionResourceState<Input, Resource>) -> Void) {
      switch state {
      case .invalid: return
      default:
         let oldPriority = _priority()
         let observer = observer ?? ConductionResourceObserver()
         _stateObserverBlocks = _stateObserverBlocks.filter { $0.id != observer }
         _stateObserverBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         _updatePriority(oldPriority: oldPriority)
      }
   }

   private func _forget(_ observer: ConductionResourceObserver) {
      let oldPriority = _priority()
      _getBlocks = _getBlocks.filter { $0.id != observer }
      _observerBlocks = _observerBlocks.filter { $0.id != observer }
      _stateObserverBlocks = _stateObserverBlocks.filter { $0.id != observer }
      _getHistory = _getHistory.filter { $0 != observer }
      _updatePriority(oldPriority: oldPriority)
   }
   
   private func _forgetAll() {
      let oldPriority = _priority()
      _getBlocks = []
      _observerBlocks = []
      _stateObserverBlocks = []
      _getHistory = []
      _updatePriority(oldPriority: oldPriority)
   }
   
   private func _check(completion: (_ state: ConductionResourceState<Input, Resource>) -> Void) {
      completion(state)
   }
   
   private func _priority() -> Int? {
      var priority: Int? = nil
      priority = _getBlocks.reduce(priority) { result, tuple in
         guard let result = result else { return tuple.priority }
         return max(result, tuple.priority)
      }
      priority = _observerBlocks.reduce(priority) { result, tuple in
         guard let result = result else { return tuple.priority }
         return max(result, tuple.priority)
      }
      priority = _stateObserverBlocks.reduce(priority) { result, tuple in
         guard let result = result else { return tuple.priority }
         return max(result, tuple.priority)
      }
      return priority
   }
   
   private func _updatePriority(oldPriority: Int?) {
      let newPriority = _priority()
      guard oldPriority != newPriority else { return }
      switch state {
      case .fetching(let id, let priority):
         guard priority != newPriority else { return }
         _transition(newState: .fetching(id: id, priority: newPriority))
      case .processing(let id, let priority, let input):
         guard priority != newPriority else { return }
         _transition(newState: .processing(id: id, priority: newPriority, input: input))
      default: break
      }
   }
   
   private func _expire() {
      switch state {
      case .empty: return
      default: _transition(newState: .empty)
      }
   }
   
   private func _invalidate() {
      switch state {
      case .invalid: return
      default: _transition(newState: .invalid(nil))
      }
   }
   
   private func _setInput(_ input: Input?) {
      _transition(newState: .processing(id: ConductionResourceFetchID(), priority: _priority(), input: input))
   }

   private func _setResource(_ resource: Resource?) {
      _transition(newState: .fetched(resource))
   }
   
   private func _fetch(id: ConductionResourceFetchID) {
      guard let fetchBlock = fetchBlock else {
         _transition(newState: .processing(id: ConductionResourceFetchID(), priority: _priority(), input: nil))
         return
      }
      
      fetchBlock(state) { [weak self] input in
         self?.dispatchQueue.async {
            guard let strongSelf = self else { return }
            switch strongSelf.state {
            case .fetching(let newID, _):
               guard id == newID else { return }
               strongSelf._transition(newState: .processing(id: ConductionResourceFetchID(), priority: strongSelf._priority(), input: input))
            default: break
            }
         }
      }
   }

   private func _process(id: ConductionResourceFetchID, input: Input?) {
      guard let transformBlock = transformBlock else {
         _transition(newState: .fetched(input as? Resource))
         return
      }
      
      transformBlock(state) { [weak self] resource in
         self?.dispatchQueue.async {
            guard let strongSelf = self else { return }
            switch strongSelf.state {
            case .processing(let newID, _, _):
               guard id == newID else { return }
               strongSelf._transition(newState: .fetched(resource))
            default: break
            }
         }
      }
   }

   private func _callWaitingBlocks(resource: Resource?) {
      var waitingBlocks: [ConductionResourceObserverEntry<Resource>] = _getBlocks
      waitingBlocks.append(contentsOf: _observerBlocks)
      waitingBlocks.sort { $0.priority > $1.priority }
      _getHistory.append(contentsOf: _getBlocks.map { return $0.id })
      _getBlocks = []
      waitingBlocks.forEach { $0.block(resource) }
   }
}

public class ConductionResource<Resource>: ConductionBaseResource<Resource, Resource> {
   public init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0, commitBlock: @escaping ConductionResourceCommitBlock<Resource, Resource> = { _, nextState, _ in return nextState }, fetchBlock: @escaping ConductionResourceFetchBlock<Resource, Resource>) {
      super.init(dispatchQueue: dispatchQueue, defaultPriority: defaultPriority, fetchBlock: fetchBlock, commitBlock: commitBlock)
   }
}
