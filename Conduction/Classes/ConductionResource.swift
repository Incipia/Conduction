//
//  ConductionResource.swift
//  Bindable
//
//  Created by Leif Meyer on 11/16/17.
//

import Foundation

public enum ConductionResourceState<Resource>: Equatable {
   case empty
   case fetching(id: ConductionResourceFetchID, priority: Int?)
   case fetched(Resource?)
   
   // MARK: - Equatable
   public static func ==(lhs: ConductionResourceState<Resource>, rhs: ConductionResourceState<Resource>) -> Bool {
      switch lhs {
      case .empty:
         switch rhs {
         case .empty: return true
         default: return false
         }
      case .fetching(let id, let priority):
         switch rhs {
         case .fetching(let rID, let rPriority): return id == rID && priority == rPriority
         default: return false
         }
      case .fetched(let resource):
         switch rhs {
         case .fetched(let rResource): return resource == nil && rResource == nil
         default: return false
         }
      }
   }
}

//public extension ConductionResourceState where Resource: Equatable {
//   // MARK: - Equatable
//   public static func ==(lhs: ConductionResourceState<Resource>, rhs: ConductionResourceState<Resource>) -> Bool {
//      switch lhs {
//      case .empty:
//         switch rhs {
//         case .empty: return true
//         default: return false
//         }
//      case .fetching(let id, let priority):
//         switch rhs {
//         case .fetching(let rID, let rPriority): return id == rID && priority == rPriority
//         default: return false
//         }
//      case .fetched(let resource):
//         switch rhs {
//         case .fetched(let rResource): return resource == rResource
//         default: return false
//         }
//      }
//   }
//}

public typealias ConductionResourceObserver = UUID

public typealias ConductionResourceFetchID = UUID

open class ConductionResource<Resource> {
   // MARK: - Private Properties
   private var _waitingBlocks: [(id: ConductionResourceObserver, priority: Int, block: (_ resource: Resource?) -> Void)] = []
   private var _history: [ConductionResourceObserver] = []
   
   // MARK: - Public Properties
   public private(set) var state: ConductionResourceState<Resource> = .empty {
      didSet {
         guard let stateChangeBlock = stateChangeBlock, oldValue != state else { return }
         stateChangeBlock(oldValue, state)
      }
   }
   public let dispatchQueue: DispatchQueue
   public let defaultPriority: Int
   public let fetchBlock: (_ priority: Int?, _ completion: @escaping (_ resource: Resource?) -> Void) -> Void
   public var invalidateBlock: () -> Resource?
   public var stateChangeBlock: ((_ oldState: ConductionResourceState<Resource>, _ newState: ConductionResourceState<Resource>) -> Void)?
   
   // MARK: - Init
   public init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0, stateChangeBlock: ((_ oldState: ConductionResourceState<Resource>, _ newState: ConductionResourceState<Resource>) -> Void)? = nil, invalidateBlock: @escaping () -> Resource? = { return nil }, fetchBlock: @escaping (_ priority: Int?, _ completion: @escaping (_ resource: Resource?) -> Void) -> Void) {
      self.dispatchQueue = dispatchQueue
      self.defaultPriority = defaultPriority
      self.stateChangeBlock = stateChangeBlock
      self.invalidateBlock = invalidateBlock
      self.fetchBlock = fetchBlock
   }
   
   // MARK: - Public
   @discardableResult public func get(observer: ConductionResourceObserver? = nil, priority: Int? = nil, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = observer ?? ConductionResourceObserver()
      dispatchQueue.async {
         self._get(observer: observer, priority: priority, completion: completion)
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
   
   public func check(completion: @escaping (_ state: ConductionResourceState<Resource>) -> Void) {
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
   
   public func setResource(_ resource: Resource?) {
      dispatchQueue.async {
         self._setResource(resource)
      }
   }
   
   // MARK: - Private
   private func _get(observer: ConductionResourceObserver, priority: Int?, completion: @escaping (_ resource: Resource?) -> Void) {
      let priority = priority ?? defaultPriority
      switch state {
      case .fetched(let resource): completion(resource)
      case .empty:
         let oldPriority = _priority()
         guard _addObserver(observer: observer, priority: priority, completion: completion) else { return }
         _fetch()
         _updatePriority(oldPriority: oldPriority)
      case .fetching:
         let oldPriority = _priority()
         guard _addObserver(observer: observer, priority: priority, completion: completion) else { return }
         _updatePriority(oldPriority: oldPriority)
      }
   }
   
   private func _addObserver(observer: ConductionResourceObserver, priority: Int, completion: @escaping (_ resource: Resource?) -> Void) -> Bool {
      guard !_history.contains(observer) else { return false }

      _waitingBlocks = _waitingBlocks.filter { $0.id != observer }
      _waitingBlocks.append((id: observer, priority: priority, block: completion))
      
      return true
   }
   
   private func _forget(_ observer: ConductionResourceObserver) {
      let oldPriority = _priority()
      _waitingBlocks = _waitingBlocks.filter { $0.id != observer }
      _history = _history.filter { $0 != observer }
      _updatePriority(oldPriority: oldPriority)
   }
   
   private func _forgetAll() {
      let oldPriority = _priority()
      _waitingBlocks = []
      _history = []
      _updatePriority(oldPriority: oldPriority)
   }
   
   private func _check(completion: @escaping (_ state: ConductionResourceState<Resource>) -> Void) {
      completion(state)
   }
   
   private func _priority() -> Int? {
      return _waitingBlocks.reduce(nil) { result, tuple in
         guard let result = result else { return tuple.priority }
         return max(result, tuple.priority)
      }
   }
   
   private func _updatePriority(oldPriority: Int?) {
      let newPriority = _priority()
      guard oldPriority != newPriority else { return }
      switch state {
      case .fetching(let id, let priority):
         if priority != newPriority {
            state = .fetching(id: id, priority: newPriority)
         }
      default: break
      }
   }
   
   private func _expire() {
      switch state {
      case .empty: return
      case .fetching: _fetch()
      case .fetched: state = .empty
      }
   }
   
   private func _invalidate() {
      switch state {
      case .empty: return
      case .fetching:
         _callWaitingBlocks(resource: invalidateBlock())
         state = .empty
      case .fetched: state = .empty
      }
   }
   
   private func _setResource(_ resource: Resource?) {
      _callWaitingBlocks(resource: resource)
      state = .fetched(resource)
   }
   
   private func _fetch() {
      let id = ConductionResourceFetchID()
      let priority = _priority()
      fetchBlock(priority) { resource in
         self.dispatchQueue.async {
            switch self.state {
            case .fetching(let fetchingID, _):
               guard fetchingID == id else { return }
               self._setResource(resource)
            default: break
            }
         }
      }
      self.state = .fetching(id: id, priority: priority)
   }
   
   private func _callWaitingBlocks(resource: Resource?) {
      let oldPriority = _priority()
      let waitingBlocks = _waitingBlocks.sorted { return $0.priority > $1.priority }
      _waitingBlocks = []
      _history.append(contentsOf: waitingBlocks.map { return $0.id })
      _updatePriority(oldPriority: oldPriority)
      waitingBlocks.forEach { $0.block(resource) }
   }
}
