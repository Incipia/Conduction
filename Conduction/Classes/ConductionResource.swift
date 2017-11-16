//
//  ConductionResource.swift
//  Bindable
//
//  Created by Leif Meyer on 11/16/17.
//

import Foundation

public enum ConductionResourceState<Resource> {
   case empty
   case fetching(UUID)
   case fetched(Resource?)
}

open class ConductionResource<Resource> {
   // MARK: - Private Properties
   private var _waitingBlocks: [(id: UUID, queue: DispatchQueue, block: (_ resource: Resource?) -> Void)] = []
   
   // MARK: - Public Properties
   public private(set) var state: ConductionResourceState<Resource> = .empty
   public var defaultDispatchQueue: DispatchQueue? = nil
   private var isFetched: Bool = false
   public var fetchBlock: (_ completion: (_ resource: Resource?) -> Void) -> Void = { completion in completion(nil) }
   public var invalidateBlock: () -> Resource? = { return nil }
   
   public var resource: Resource? {
      get {
         switch state {
         case .fetched(let resource): return resource
         default: return nil
         }
      }
      set {
         state = .fetched(newValue)
         _callWaitingBlocks(resource: newValue)
      }
   }
   
   // MARK: - Public
   func get(async: Bool = true, dispatchQueue: DispatchQueue? = nil, completion: @escaping (_ resource: Resource?) -> Void) {
      let id = UUID()
      let queue = dispatchQueue ?? defaultDispatchQueue ?? .main
      switch state {
      case .fetched(let resource):
         switch async {
         case true:
            queue.async {
               completion(resource)
            }
         case false: completion(resource)
         }
         return
      case .empty:
         _waitingBlocks.append((id: id, queue: queue, block: completion))
         _fetch()
      case .fetching: _waitingBlocks.append((id: id, queue: queue, block: completion))
      }
   }
   
   func expire() {
      switch state {
      case .empty: return
      case .fetching: _fetch()
      case .fetched: state = .empty
      }
   }
   
   func invalidate() {
      switch state {
      case .empty: return
      case .fetching:
         state = .empty
         _callWaitingBlocks(resource: invalidateBlock())
      case .fetched: state = .empty
      }
   }
   
   // MARK: - Private
   private func _fetch() {
      let id = UUID()
      state = .fetching(id)
      fetchBlock { resource in
         switch self.state {
         case .fetching(let fetchingID):
            guard fetchingID == id else { return }
            self.state = .fetched(resource)
            _callWaitingBlocks(resource: resource)
         default: break
         }
      }
   }
   
   private func _callWaitingBlocks(resource: Resource?) {
      let waitingBlocks = _waitingBlocks;
      _waitingBlocks = []
      waitingBlocks.forEach { tuple in
         tuple.queue.async {
            tuple.block(resource)
         }
      }
   }
}
