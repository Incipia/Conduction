//
//  ConductionRoute.swift
//  Bindable
//
//  Created by Leif Meyer on 2/3/18.
//

import Foundation

public enum ConductionRouteComponent: Equatable {
   case path(String)
   case routing(ConductionRouting)
   case nonRouting(String, Any?)
   
   // MARK: - Public Properties
   public var routingName: String {
      switch self {
      case .path(let name): return name
      case .routing(let router): return router.routingName
      case .nonRouting(let name, _): return name
      }
   }
   
   // MARK: - Equatable
   public static func ==(lhs: ConductionRouteComponent, rhs: ConductionRouteComponent) -> Bool {
      return lhs.routingName == rhs.routingName
   }
}

public struct ConductionRoute: Equatable, RawRepresentable {
   // MARK: - Public Properties
   public var components: [ConductionRouteComponent] = []

   // MARK: - Init
   public init() {}
   
   public init(components: [ConductionRouteComponent]) {
      self.components = components
   }
   
   // MARK: - Public
   public func forwardRouteUpdate(route: ConductionRoute, completion: ((_ success: Bool) -> Void)?) -> Bool {
      guard route != self else {
         completion?(true)
         return true
      }
      var lastRouter: (router: ConductionRouting, index: Int)? = nil
      for (index, component) in components.enumerated() {
         if index >= route.components.count || component != route.components[index] {
            break
         }
         switch component {
         case .routing(let router): lastRouter = (router: router, index: index)
         default: break
         }
      }
      guard let router = lastRouter else { return false }
      let remainingComponents = router.index < route.components.count ? Array(route.components.suffix(from: router.index + 1)) : []
      router.router.update(newRoute: ConductionRoute(components: remainingComponents), completion: completion)
      return true
   }
   
   // MARK: - Operators
   public static func +(lhs: ConductionRoute, rhs: ConductionRoute) -> ConductionRoute {
      var components = lhs.components
      components.append(contentsOf: rhs.components)
      return ConductionRoute(components: components)
   }
   
   // MARK: - Equatable
   public static func ==(lhs: ConductionRoute, rhs: ConductionRoute) -> Bool {
      return lhs.components == rhs.components
   }
   
   // MARK: - RawRepresentable
   public init?(rawValue: String) {
      components = rawValue.split(separator: "/").map { .path(String($0)) }
   }
   
   public var rawValue: String {
      return components.map { $0.routingName }.joined(separator: "/")
   }
}

public protocol ConductionRouting: class {
   // MARK: - Public Properties
   var routingName: String { get }
   var route: ConductionRoute { get }
   var navigationContext: UINavigationController? { get }
   var modalContext: UIViewController? { get }
   weak var routeParent: ConductionRouting? { get set }
   var routeChild: ConductionRouting? { get set }
   
   // MARK: - Public
   @discardableResult func appendRouteChild(_ conductionRouting: ConductionRouting, animated: Bool) -> Bool
   func routeChildRemoved(animated: Bool)
   func update(newRoute: ConductionRoute, completion: ((_ success: Bool) -> Void)?)
   func showInRoute(routeContext: ConductionRouting, animated: Bool) -> Bool
   @discardableResult func dismissFromRoute(animated: Bool) -> Bool
}

public extension ConductionRouting {
   // MARK: - Public Properties
   var childRoute: ConductionRoute {
      guard let routeChild = routeChild else { return ConductionRoute() }
      return ConductionRoute(components: [.routing(routeChild)]) + routeChild.route
   }
   
   // MARK: - ConductionRouting
   var routingName: String { return "" }
   var route: ConductionRoute { return childRoute }
   var navigationContext: UINavigationController? { return nil }
   var modalContext: UIViewController? { return nil }

   func showInRoute(routeContext: ConductionRouting, animated: Bool) -> Bool {
      routeParent = routeContext
      return true
   }
   
   @discardableResult func dismissFromRoute(animated: Bool) -> Bool {
      routeParent?.routeChildRemoved(animated: animated)
      routeParent = nil
      return true
   }
   
   @discardableResult func appendRouteChild(_ conductionRouting: ConductionRouting, animated: Bool) -> Bool {
      if let routeChild = routeChild {
         return routeChild.appendRouteChild(conductionRouting, animated: animated)
      }
      guard conductionRouting.showInRoute(routeContext: self, animated: animated) else { return false }
      routeChild = conductionRouting
      return true
   }
   
   func routeChildRemoved(animated: Bool) {
      routeChild = nil
   }
   
   // MARK: - Public
   func update(newRoute: ConductionRoute, completion: ((_ success: Bool) -> Void)? = nil) {
      guard !self.route.forwardRouteUpdate(route: newRoute, completion: completion) else { return }
      completion?(false)
   }
}
