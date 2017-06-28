//
//  ConductionWrapper.swift
//  Bindable
//
//  Created by Gregory Klein on 6/28/17.
//

import Foundation

open class StaticConductionWrapper<DataModel> {
   // MARK: - Public Properties
   public let model: DataModel
   
   // MARK: - Init
   public init(model: DataModel) {
      self.model = model
   }
}

open class StatelessConductionWrapper<DataModel> {
   // MARK: - Public Properties
   public var model: DataModel {
      didSet { onChange?(oldValue, model) }
   }
   
   public var onChange: ((DataModel, DataModel) -> Void)? {
      didSet { onChange?(model, model) }
   }
   
   // MARK: - Init
   public init(model: DataModel) {
      self.model = model
   }
}

open class ConductionWrapper<DataModel, State: ConductionState>: ConductionStateObserver<State> {
   // MARK: - Public Properties
   public var model: DataModel {
      didSet { valueChanged() }
   }
   
   // MARK: - Init
   public init(model: DataModel) {
      self.model = model
      super.init()
   }
}
