//
//  ConductionResource.swift
//  Bindable
//
//  Created by Leif Meyer on 11/16/17.
//

import Foundation

public enum ConductionResourceState<Resource> {
   case empty
   case fetching(ConductionResourceObserver)
   case fetched(Resource?)
}

public typealias ConductionResourceObserver = UUID

open class ConductionResource<Resource> {
   // MARK: - Private Properties
   private var _waitingBlocks: [(id: ConductionResourceObserver, priority: Int, block: (_ resource: Resource?) -> Void)] = []
   
   // MARK: - Public Properties
   public private(set) var state: ConductionResourceState<Resource> = .empty
   public let dispatchQueue: DispatchQueue
   public let defaultPriority: Int
   private var isFetched: Bool = false
   public var fetchBlock: (_ completion: (_ resource: Resource?) -> Void) -> Void = { completion in completion(nil) }
   public var invalidateBlock: () -> Resource? = { return nil }
   public var priorityChangeBlock: ((_ oldPriority: Int?, _ newPriority: Int?) -> Void)?
   
   // MARK: - Init
   init(dispatchQueue: DispatchQueue = .main, defaultPriority: Int = 0) {
      self.dispatchQueue = dispatchQueue
      self.defaultPriority = defaultPriority
   }
   
   // MARK: - Public
   func get(priority: Int? = nil, completion: @escaping (_ resource: Resource?) -> Void) -> ConductionResourceObserver {
      let observer = ConductionResourceObserver()
      dispatchQueue.async {
         self._get(observer: observer, priority: priority, completion: completion)
      }
      return observer
   }
   
   func forget(_ observer: ConductionResourceObserver) {
      dispatchQueue.async {
         self._forget(observer)
      }
   }
   
   func expire() {
      dispatchQueue.async {
         self._expire()
      }
   }
   
   func invalidate() {
      dispatchQueue.async {
         self._invalidate()
      }
   }
   
   func setResource(_ resource: Resource?) {
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
         _addObserver(observer: observer, priority: priority, completion: completion)
         _fetch()
      case .fetching: _addObserver(observer: observer, priority: priority, completion: completion)
      }
   }
   
   private func _addObserver(observer: ConductionResourceObserver, priority: Int, completion: @escaping (_ resource: Resource?) -> Void) {
      let oldPriority = _priority()
      _waitingBlocks.append((id: observer, priority: priority, block: completion))
      _updatePriority(oldPriority: oldPriority)
   }
   
   private func _forget(_ observer: ConductionResourceObserver) {
      let oldPriority = _priority()
      _waitingBlocks = _waitingBlocks.filter { $0.id != observer }
      _updatePriority(oldPriority: oldPriority)
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
      priorityChangeBlock?(oldPriority, newPriority)
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
         state = .empty
         _callWaitingBlocks(resource: invalidateBlock())
      case .fetched: state = .empty
      }
   }
   
   private func _setResource(_ resource: Resource?) {
      state = .fetched(resource)
      _callWaitingBlocks(resource: resource)
   }
   
   private func _fetch() {
      let id = UUID()
      state = .fetching(id)
      fetchBlock { resource in
         switch self.state {
         case .fetching(let fetchingID):
            guard fetchingID == id else { return }
            _setResource(resource)
         default: break
         }
      }
   }
   
   private func _callWaitingBlocks(resource: Resource?) {
      let oldPriority = _priority()
      let waitingBlocks = _waitingBlocks.sorted { return $0.priority > $1.priority }
      _waitingBlocks = []
      _updatePriority(oldPriority: oldPriority)
      waitingBlocks.forEach { $0.block(resource) }
   }
}
