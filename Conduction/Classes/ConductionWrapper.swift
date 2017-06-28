//
//  ConductionWrapper.swift
//  Bindable
//
//  Created by Gregory Klein on 6/28/17.
//

import Foundation

open class ConductionDataWrapper<DataModel> {
   // MARK: - Public Properties
   public let model: DataModel
   
   // MARK: - Init
   public init(model: DataModel) {
      self.model = model
   }
}

open class ConductionWrapper<DataModel> {
   // MARK: - Public Properties
   public var model: DataModel! {
      didSet { onChange?() }
   }
   
   public var onChange: (() -> Void)? {
      didSet { onChange?() }
   }
   
   public var isEmpty: Bool { return model == nil }
   
   // MARK: - Init
   public init() {}
   
   public init(model: DataModel) {
      self.model = model
   }
}

open class ConductionStateWrapper<DataModel, State: ConductionModelState>: ConductionStateModel<State> {
   // MARK: - Public Properties
   public var model: DataModel! {
      didSet { valueChanged() }
   }
   
   public var isEmpty: Bool { return model == nil }
   
   // MARK: - Init
   public init(model: DataModel) {
      self.model = model
      super.init()
   }
}
