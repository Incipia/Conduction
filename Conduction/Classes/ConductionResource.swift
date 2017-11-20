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
   public private(set) var input: Input?
   public private(set) var resource: Resource?
   
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
         self.directGet(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }

   @discardableResult public func observe(observer: ConductionResourceObserver? = nil, priority: Int? = nil, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatchQueue.async {
         self.directObserve(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }

   @discardableResult public func observeState(observer: ConductionResourceObserver? = nil, priority: Int? = nil, completion: @escaping (_ oldState: ConductionResourceState<Input, Resource>, _ newState: ConductionResourceState<Input, Resource>) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatchQueue.async {
         self.directObserveState(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }

   public func forget(_ observer: ConductionResourceObserver) {
      dispatchQueue.async {
         self.directForget(observer)
      }
   }
   
   public func forgetAll() {
      dispatchQueue.async {
         self.directForgetAll()
      }
   }
   
   public func check(completion: @escaping (_ state: ConductionResourceState<Input, Resource>, _ priority: Int?, _ input: Input?, _ resource: Resource?) -> Void) {
      dispatchQueue.async {
         self.directCheck(completion: completion)
      }
   }
   
   public func expire() {
      dispatchQueue.async {
         self.directExpire()
      }
   }
   
   public func invalidate() {
      dispatchQueue.async {
         self.directInvalidate()
      }
   }
   
   public func setInput( _ input: Input?) {
      dispatchQueue.async {
         self.directSetInput(input)
      }
   }
   
   public func setResource(_ resource: Resource?) {
      dispatchQueue.async {
         self.directSetResource(resource)
      }
   }
   
   // MARK: - Direct
   open func directTransition(newState: ConductionResourceState<Input, Resource>, input: Input? = nil) {
      let oldState = state
      guard let nextState = commitBlock(oldState, newState, input) else { return }
      state = nextState
      switch state {
      case .invalid(let resource):
         self.resource = resource
         _callWaitingBlocks()
         forgetAll()
      case .empty: break
      case .fetching(let id, _):
         switch oldState {
         case .fetching(let oldID, _): guard id != oldID else { return }
         default: break
         }
         _fetch(id: id)
      case .processing(let id, _, let input):
         self.input = input
         switch oldState {
         case .processing(let oldID, _, _): guard id != oldID else { return }
         default: break
         }
         _process(id: id, input: input)
      case .fetched(let resource):
         self.resource = resource
         _callWaitingBlocks()
      }
   }
   
   @discardableResult open func directGet(observer: ConductionResourceObserver? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      guard !_getHistory.contains(observer) else { return observer }
      guard !callNow else {
         completion(resource)
         return observer
      }
      
      switch state {
      case .invalid: return observer
      case .fetched:
         completion(resource)
         return observer
      default:
         let oldPriority = _priority()
         _getBlocks = _getBlocks.filter { $0.id != observer }
         _getBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         switch state {
         case .empty: directTransition(newState: .fetching(id: ConductionResourceFetchID(), priority: _priority()))
         case .fetching, .processing: _updatePriority(oldPriority: oldPriority)
         default: break
         }
      }
      
      return observer
   }
   
   @discardableResult open func directObserve(observer: ConductionResourceObserver? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()

      switch state {
      case .invalid: return observer
      default:
         let oldPriority = _priority()
         _observerBlocks = _observerBlocks.filter { $0.id != observer }
         _observerBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         _updatePriority(oldPriority: oldPriority)
         if callNow {
            completion(resource)
         } else {
            switch state {
            case .fetched: completion(resource)
            default: break
            }
         }
      }
      
      return observer
   }

   @discardableResult open func directObserveState(observer: ConductionResourceObserver? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ oldState: ConductionResourceState<Input, Resource>, _ newState: ConductionResourceState<Input, Resource>) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()

      switch state {
      case .invalid: return observer
      default:
         let oldPriority = _priority()
         _stateObserverBlocks = _stateObserverBlocks.filter { $0.id != observer }
         _stateObserverBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         _updatePriority(oldPriority: oldPriority)
         if callNow {
            completion(state, state)
         }
      }
      
      return observer
   }

   open func directForget(_ observer: ConductionResourceObserver) {
      let oldPriority = _priority()
      _getBlocks = _getBlocks.filter { $0.id != observer }
      _observerBlocks = _observerBlocks.filter { $0.id != observer }
      _stateObserverBlocks = _stateObserverBlocks.filter { $0.id != observer }
      _getHistory = _getHistory.filter { $0 != observer }
      _updatePriority(oldPriority: oldPriority)
   }
   
   open func directForgetAll() {
      let oldPriority = _priority()
      _getBlocks = []
      _observerBlocks = []
      _stateObserverBlocks = []
      _getHistory = []
      _updatePriority(oldPriority: oldPriority)
   }
   
   open func directCheck(completion: (_ state: ConductionResourceState<Input, Resource>, _ priority: Int?, _ input: Input?, _ resource: Resource?) -> Void) {
      completion(state, _priority(), input, resource)
   }
   
   open func directExpire() {
      switch state {
      case .empty: return
      default: directTransition(newState: .empty)
      }
   }
   
   open func directInvalidate() {
      switch state {
      case .invalid: return
      default: directTransition(newState: .invalid(nil))
      }
   }
   
   open func directSetInput(_ input: Input?) {
      directTransition(newState: .processing(id: ConductionResourceFetchID(), priority: _priority(), input: input))
   }
   
   open func directSetResource(_ resource: Resource?) {
      directTransition(newState: .fetched(resource))
   }

   // MARK: - Private
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
         directTransition(newState: .fetching(id: id, priority: newPriority))
      case .processing(let id, let priority, let input):
         guard priority != newPriority else { return }
         directTransition(newState: .processing(id: id, priority: newPriority, input: input))
      default: break
      }
   }
   
   private func _fetch(id: ConductionResourceFetchID) {
      guard let fetchBlock = fetchBlock else {
         directTransition(newState: .processing(id: ConductionResourceFetchID(), priority: _priority(), input: nil))
         return
      }
      
      fetchBlock(state) { [weak self] input in
         self?.dispatchQueue.async {
            guard let strongSelf = self else { return }
            switch strongSelf.state {
            case .fetching(let newID, _):
               guard id == newID else { return }
               strongSelf.directTransition(newState: .processing(id: ConductionResourceFetchID(), priority: strongSelf._priority(), input: input))
            default: break
            }
         }
      }
   }

   private func _process(id: ConductionResourceFetchID, input: Input?) {
      guard let transformBlock = transformBlock else {
         directTransition(newState: .fetched(input as? Resource))
         return
      }
      
      transformBlock(state) { [weak self] resource in
         self?.dispatchQueue.async {
            guard let strongSelf = self else { return }
            switch strongSelf.state {
            case .processing(let newID, _, _):
               guard id == newID else { return }
               strongSelf.directTransition(newState: .fetched(resource))
            default: break
            }
         }
      }
   }

   private func _callWaitingBlocks() {
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
