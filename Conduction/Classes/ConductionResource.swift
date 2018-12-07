//
//  ConductionResource.swift
//  Bindable
//
//  Created by Leif Meyer on 11/16/17.
//

import Foundation

public enum ConductionResourceState<Parameter, Input, Resource> {
   case empty
   case fetching(id: ConductionResourceTaskID, priority: Int?, parameter: Parameter?)
   case processing(id: ConductionResourceTaskID, priority: Int?, input: Input?)
   case fetched(Resource?)
   case invalid(Resource?)
   
   // MARK: - Public Properties
   public var priority: Int? {
      switch self {
      case .fetching(_, let priority, _): return priority
      case .processing(_, let priority, _): return priority
      default: return nil
      }
   }

   public var parameter: Parameter? {
      switch self {
      case .fetching(_, _, let parameter): return parameter
      default: return nil
      }
   }

   public var input: Input? {
      switch self {
      case .processing(_, _, let input): return input
      default: return nil
      }
   }

   public var resource: Resource? {
      switch self {
      case .fetched(let resource): return resource
      default: return nil
      }
   }
}

public typealias ConductionResourceObserver = UUID

public typealias ConductionResourceTaskID = UUID

public typealias ConductionResourceFetchBlock<Parameter, Input> = (_ parameter: Parameter?, _ priority: Int?, _ completion: @escaping (_ fetchedInput: Input?) -> Void) -> Void

public typealias ConductionResourceTransformBlock<Input, Resource> = (_ input: Input?, _ priority: Int?, _ completion: @escaping (_ resource: Resource?) -> Void) -> Void

public typealias ConductionResourceCommitBlock<Parameter, Input, Resource> = (_ state: ConductionResourceState<Parameter, Input, Resource>, _ nextState: ConductionResourceState<Parameter, Input, Resource>) -> ConductionResourceState<Parameter, Input, Resource>?

public typealias ConductionResourceObserverBlock<Resource> = (_ resource: Resource?) -> Void

fileprivate typealias ConductionResourceObserverEntry<Resource> = (id: ConductionResourceObserver, priority: Int, block: ConductionResourceObserverBlock<Resource>)

open class ConductionBaseResource<Parameter, Input, Resource> {
   // MARK: - Private Properties
   private var _getBlocks: [ConductionResourceObserverEntry<Resource>] = []
   private var _observerBlocks: [ConductionResourceObserverEntry<Resource>] = []
   private var _stateObserverBlocks: [(id: ConductionResourceObserver, priority: Int, block: (_ oldState: ConductionResourceState<Parameter, Input, Resource>, _ newState: ConductionResourceState<Parameter, Input, Resource>) -> Void)] = []
   private var _getHistory: [ConductionResourceObserver] = []
   private var _dispatchKey = DispatchSpecificKey<Void>()

   
   // MARK: - Public Properties
   public private(set) var state: ConductionResourceState<Parameter, Input, Resource> = .empty {
      didSet {
         _stateObserverBlocks.sorted { $0.priority > $1.priority }.forEach { $0.block(oldValue, state) }
      }
   }
   public let dispatchQueue: DispatchQueue
   public let defaultPriority: Int
   public let fetchBlock: ConductionResourceFetchBlock<Parameter, Input>?
   public let transformBlock: ConductionResourceTransformBlock<Input, Resource>?
   public let commitBlock: ConductionResourceCommitBlock<Parameter, Input, Resource>
   public private(set) var parameter: Parameter?
   public private(set) var input: Input?
   public private(set) var resource: Resource?
   
   // MARK: - Init
   public init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0, fetchBlock: ConductionResourceFetchBlock<Parameter, Input>? = nil, transformBlock: ConductionResourceTransformBlock<Input, Resource>? = nil, commitBlock: @escaping ConductionResourceCommitBlock<Parameter, Input, Resource> = { _, nextState in return nextState }) {
      dispatchQueue.setSpecific(key: _dispatchKey, value: ())
      self.dispatchQueue = dispatchQueue
      self.defaultPriority = defaultPriority
      self.fetchBlock = fetchBlock
      self.transformBlock = transformBlock
      self.commitBlock = commitBlock
   }
   
   // MARK: - Public
   @discardableResult public func get(observer: ConductionResourceObserver? = nil, parameter: Parameter? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatch {
         self.directGet(observer: observer, parameter: parameter, priority: priority, callNow: callNow, completion: completion)
      }
      return observer
   }

   @discardableResult public func observe(observer: ConductionResourceObserver? = nil, parameter: Parameter? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatch {
         self.directObserve(observer: observer, parameter: parameter, priority: priority, callNow: callNow, completion: completion)
      }
      return observer
   }

   @discardableResult public func observeState(observer: ConductionResourceObserver? = nil, parameter: Parameter? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ oldState: ConductionResourceState<Parameter, Input, Resource>, _ newState: ConductionResourceState<Parameter, Input, Resource>) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatch {
         self.directObserveState(observer: observer, priority: priority, callNow: callNow, completion: completion)
      }
      return observer
   }

   public func forget(_ observer: ConductionResourceObserver) {
     dispatch {
         self.directForget(observer)
      }
   }
   
   public func forgetAll() {
      dispatch {
         self.directForgetAll()
      }
   }
   
   public func check(completion: @escaping (_ state: ConductionResourceState<Parameter, Input, Resource>, _ priority: Int?, _ parameter: Parameter?, _ input: Input?, _ resource: Resource?) -> Void) {
      dispatch {
         self.directCheck(completion: completion)
      }
   }
   
   public func load(parameter: Parameter? = nil) {
      dispatch {
         self.directLoad(parameter: parameter)
      }
   }

   public func reload(parameter: Parameter? = nil) {
      dispatch {
         self.directReload(parameter: parameter)
      }
   }

   public func clear() {
      dispatch {
         self.directClear()
      }
   }
   
   public func expire() {
      dispatch {
         self.directExpire()
      }
   }
   
   public func invalidate() {
      dispatch {
         self.directInvalidate()
      }
   }

   public func setParameter( _ parameter: Parameter?) {
      dispatch {
         self.directSetParameter(parameter)
      }
   }

   public func setInput( _ input: Input?) {
      dispatch {
         self.directSetInput(input)
      }
   }
   
   public func setResource(_ resource: Resource?) {
      dispatch {
         self.directSetResource(resource)
      }
   }
   
   public func dispatch(_ block: @escaping () -> Void) {
      if DispatchQueue.getSpecific(key: _dispatchKey) != nil {
         block()
      } else {
         dispatchQueue.async {
            block()
         }
      }
   }

   // MARK: - Direct
   open func directTransition(newState: ConductionResourceState<Parameter, Input, Resource>) {
      let oldState = state
      guard let nextState = commitBlock(oldState, newState) else { return }
      state = nextState
      switch state {
      case .invalid(let resource):
         self.resource = resource
         _callWaitingBlocks()
         forgetAll()
      case .empty: break
      case .fetching(let id, _, let parameter):
         self.parameter = parameter
         switch oldState {
         case .fetching(let oldID, _, _): guard id != oldID else { return }
         default: break
         }
         _fetch(id: id)
      case .processing(let id, _, let input):
         self.input = input
         switch oldState {
         case .processing(let oldID, _, _): guard id != oldID else { return }
         default: break
         }
         _process(id: id)
      case .fetched(let resource):
         self.resource = resource
         _callWaitingBlocks()
      }
   }
   
   @discardableResult open func directGet(observer: ConductionResourceObserver? = nil, parameter: Parameter? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      guard !_getHistory.contains(observer) else { return observer }
      guard !callNow else {
         completion(resource)
         return observer
      }
      
      switch state {
      case .invalid: return observer
      case .fetched:
         guard parameter != nil else {
            completion(resource)
            return observer
         }
         fallthrough
      default:
         let oldPriority = _priority()
         _getBlocks = _getBlocks.filter { $0.id != observer }
         _getBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         switch state {
         case .fetching, .processing:
            guard parameter != nil else {
               _updatePriority(oldPriority: oldPriority)
               return observer
            }
            fallthrough
         default: directTransition(newState: .fetching(id: ConductionResourceTaskID(), priority: _priority(), parameter: parameter))
         }
      }
      
      return observer
   }
   
   @discardableResult open func directObserve(observer: ConductionResourceObserver? = nil, parameter: Parameter? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()

      switch state {
      case .invalid: return observer
      default:
         let oldPriority = _priority()
         _observerBlocks = _observerBlocks.filter { $0.id != observer }
         _observerBlocks.append((id: observer, priority: priority ?? defaultPriority, block: completion))
         _updatePriority(oldPriority: oldPriority)
         if let parameter = parameter {
            directTransition(newState: .fetching(id: ConductionResourceTaskID(), priority: _priority(), parameter: parameter))
         } else if callNow {
            completion(resource)
         } else {
            switch state {
            case .fetched:
               completion(resource)
            default: break
            }
         }
      }
      
      return observer
   }

   @discardableResult open func directObserveState(observer: ConductionResourceObserver? = nil, priority: Int? = nil, callNow: Bool = false, completion: @escaping (_ oldState: ConductionResourceState<Parameter, Input, Resource>, _ newState: ConductionResourceState<Parameter, Input, Resource>) -> Void) -> ConductionResourceObserver {
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
   
   open func directCheck(completion: (_ state: ConductionResourceState<Parameter, Input, Resource>, _ priority: Int?, _ parameter: Parameter?, _ input: Input?, _ resource: Resource?) -> Void) {
      completion(state, _priority(), parameter, input, resource)
   }
   
   open func directLoad(parameter: Parameter? = nil) {
      switch state {
      case .invalid: return
      case .empty: directTransition(newState: .fetching(id: ConductionResourceTaskID(), priority: _priority(), parameter: parameter))
      default: break
      }
   }

   open func directReload(parameter: Parameter? = nil) {
      switch state {
      case .invalid: return
      default: directTransition(newState: .fetching(id: ConductionResourceTaskID(), priority: _priority(), parameter: parameter))
      }
   }

   open func directClear() {
      parameter = nil
      input = nil
      resource = nil
      directExpire()
   }

   open func directExpire() {
      switch state {
      case .invalid: return
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

   open func directSetParameter(_ parameter: Parameter?) {
      directTransition(newState: .fetching(id: ConductionResourceTaskID(), priority: _priority(), parameter: parameter))
   }

   open func directSetInput(_ input: Input?) {
      directTransition(newState: .processing(id: ConductionResourceTaskID(), priority: _priority(), input: input))
   }
   
   open func directSetResource(_ resource: Resource?) {
      directTransition(newState: .fetched(resource))
   }
   
   // MARK: - Life Cycle
   deinit {
      dispatchQueue.setSpecific(key: _dispatchKey, value: nil)
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
      case .fetching(let id, let priority, let parameter):
         guard priority != newPriority else { return }
         directTransition(newState: .fetching(id: id, priority: newPriority, parameter: parameter))
      case .processing(let id, let priority, let input):
         guard priority != newPriority else { return }
         directTransition(newState: .processing(id: id, priority: newPriority, input: input))
      default: break
      }
   }
   
   private func _fetch(id: ConductionResourceTaskID) {
      guard let fetchBlock = fetchBlock else {
         directTransition(newState: .processing(id: ConductionResourceTaskID(), priority: _priority(), input: state.parameter as? Input))
         return
      }
      
      fetchBlock(state.parameter, state.priority) { input in
         self.dispatch {
            switch self.state {
            case .fetching(let newID, _, _):
               guard id == newID else { return }
               self.directTransition(newState: .processing(id: ConductionResourceTaskID(), priority: self._priority(), input: input))
            default: break
            }
         }
      }
   }

   private func _process(id: ConductionResourceTaskID) {
      guard let transformBlock = transformBlock else {
         directTransition(newState: .fetched(state.input as? Resource))
         return
      }
      
      transformBlock(state.input, state.priority) { resource in
         self.dispatch {
            switch self.state {
            case .processing(let newID, _, _):
               guard id == newID else { return }
               self.directTransition(newState: .fetched(resource))
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

open class ConductionTransformedResource<Input, Resource>: ConductionBaseResource<Void, Input, Resource> {
   public init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0, commitBlock: @escaping ConductionResourceCommitBlock<Void, Input, Resource> = { _, nextState in return nextState }, fetchBlock: @escaping ConductionResourceFetchBlock<Void, Input>, transformBlock: @escaping ConductionResourceTransformBlock<Input, Resource>) {
      super.init(dispatchQueue: dispatchQueue, defaultPriority: defaultPriority, fetchBlock: fetchBlock, transformBlock: transformBlock, commitBlock: commitBlock)
   }
}

open class ConductionResource<Resource>: ConductionBaseResource<Void, Resource, Resource> {
   public init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0, commitBlock: @escaping ConductionResourceCommitBlock<Void, Resource, Resource> = { _, nextState in return nextState }, fetchBlock: @escaping ConductionResourceFetchBlock<Void, Resource>) {
      super.init(dispatchQueue: dispatchQueue, defaultPriority: defaultPriority, fetchBlock: fetchBlock, commitBlock: commitBlock)
   }
}
