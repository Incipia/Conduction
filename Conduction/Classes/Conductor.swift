//
//  Conductor.swift
//  GigSalad
//
//  Created by Gregory Klein on 2/13/17.
//  Copyright © 2017 Incipia. All rights reserved.
//

import UIKit

/*
 Conductor: A class that owns one or more view controllers, acts as their delegate if applicable, and encompasses the logic
         that's used for navigating the user through a specific 'flow'
 */

open class Conductor: NSObject, ConductionRouting {
   public weak var context: UINavigationController?
   public weak var alertContext: UIViewController?
   weak var topBeforeShowing: UIViewController?
   weak var previousContextDelegate: UINavigationControllerDelegate?

   public var willShowBlock: (() -> Void) = {}
   public var showBlock: (() -> Void) = {}

   public var willDismissBlock: (() -> Void) = {}
   public var dismissBlock: (() -> Void) = {}

   fileprivate var _isShowing: Bool = false
   fileprivate var _resetCompletion: (() -> Void)?
   fileprivate var _dismissCompletion: (() -> Void)?

   // Meant to be overridden
   open var rootViewController: UIViewController? {
      fatalError("\(#function) needs to be overridden")
   }
   
   open func conductorWillShow(in context: UINavigationController) {
   }
   
   open func conductorDidShow(in context: UINavigationController) {
   }
   
   open func conductorWillDismiss(from context: UINavigationController) {
   }
   
   open func conductorDidDismiss(from context: UINavigationController) {
   }
   
   public func show(conductor: Conductor?, animated: Bool = true) {
      guard let context = self.context else { return }
      conductor?.show(with: context, animated: animated)
   }
   
   public func show(with context: UINavigationController, animated: Bool = false) {
      guard self.context == nil else { fatalError("Conductor (\(self)) already has a context: \(String(describing: self.context))") }
      guard let rootViewController = rootViewController else { fatalError("Conductor (\(self)) has no root view controller") }
      self.context = context
      self.topBeforeShowing = context.topViewController
      
      previousContextDelegate = context.delegate
      context.delegate = self
      context.pushViewController(rootViewController, animated: animated)
   }
   
   @objc public func dismiss() {
      if let routeParent = routeParent {
         routeParent.routeChildRemoved(animated: topBeforeShowing != nil)
      }
      guard let topBeforeShowing = topBeforeShowing else {
         _dismissCompletion?()
         _dismissCompletion = nil
         return
      }
      _ = context?.popToViewController(topBeforeShowing, animated: true)
   }
   
   public func dismissWithCompletion(_ completion: @escaping (() -> Void)) {
      _dismissCompletion = completion
      dismiss()
   }
   
   @discardableResult @objc public func reset() -> Bool {
      guard let rootViewController = rootViewController else {
         _resetCompletion?()
         _resetCompletion = nil
         return false
      }
      _ = context?.popToViewController(rootViewController, animated: true)
      return true
   }

   @discardableResult @objc public func resetWithCompletion(_ completion: @escaping (() -> Void)) -> Bool {
      _resetCompletion = completion
      return reset()
   }

   fileprivate func _dismiss() {
      guard _isShowing else { fatalError("\(#function) called when \(self) is not showing") }
      
      _isShowing = false
      context?.delegate = previousContextDelegate
      previousContextDelegate = nil
      context = nil
      if let dismissCompletion = _dismissCompletion {
         dismissCompletion()
         _dismissCompletion = nil
      }
      dismissBlock()
   }
   
   // MARK: - ConductionRouting
   open var routingName: String { return "" }
   open var routeParent: ConductionRouting?
   open var routeChild: ConductionRouting?
   open var navigationContext: UINavigationController? { return context }
   open var modalContext: UIViewController? { return context?.topViewController }
   
   open func showInRoute(routeContext: ConductionRouting, animated: Bool) -> Bool {
      guard let navigationContext = routeContext.navigationContext else { return false }
      routeParent = routeContext
      show(with: navigationContext, animated: animated)
      return true
   }
   
   open func dismissFromRoute(animated: Bool) -> Bool {
      dismiss()
      return true
   }
   
   open func update(newRoute: ConductionRoute, completion: ((Bool) -> Void)?) {
      guard !self.route.forwardRouteUpdate(route: newRoute, completion: completion) else { return }
      completion?(false)
   }
}

open class TabConductor: Conductor {
   public weak var tabBarController: UITabBarController?
   
   public var tabBarContext: UINavigationController? {
      return tabBarController?.navigationController
   }
   
   public func show(in tabBarController: UITabBarController, with context: UINavigationController, animated: Bool = false) {
      show(with: context)
      var vcs: [UIViewController] = tabBarController.viewControllers ?? []
      vcs.append(context)
      tabBarController.viewControllers = vcs
      self.tabBarController = tabBarController
   }
   
   public func show() {
      guard let context = context, let index = tabBarController?.viewControllers?.index(of: context) else { return }
      tabBarController?.selectedIndex = index
   }
   
   override public func dismiss() {
      guard let context = context, var viewControllers = tabBarController?.viewControllers else { return }
      guard let index = viewControllers.index(of: context) else { return }
      viewControllers.remove(at: index)
      tabBarController?.setViewControllers(viewControllers, animated: false)
   }
}

extension Conductor: UINavigationControllerDelegate {
   open func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
      // check to see if the navigation controller is popping to it's root view controller
      guard let rootViewController = rootViewController else { fatalError() }
      let previousDelegate = previousContextDelegate
      
      if _conductorIsBeingPoppedOffContext(byShowing: viewController) {
         conductorWillDismiss(from: navigationController)
         willDismissBlock()
      }
      
      if !_isShowing, rootViewController == viewController {
         conductorWillShow(in: navigationController)
         willShowBlock()
      }
      
      previousDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
   }
   
   open func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
      weak var previousDelegate = previousContextDelegate
      defer {
         previousDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
      }
      guard let rootViewController = rootViewController else { return }
      if !_isShowing, rootViewController == viewController {
         conductorDidShow(in: navigationController)
         _isShowing = true
         showBlock()
      }
      
      if _isShowing, rootViewController == viewController, let resetCompletion = _resetCompletion {
         resetCompletion()
         _resetCompletion = nil
      }
      
      if _conductorIsBeingPoppedOffContext(byShowing: viewController) {
         _dismiss()
         conductorDidDismiss(from: navigationController)
      }
   }
   
   open func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
      return previousContextDelegate?.navigationController?(navigationController, interactionControllerFor: animationController)
   }
   
   open func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationControllerOperation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
      return previousContextDelegate?.navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
   }
   
   private func _conductorIsBeingPoppedOffContext(byShowing viewController: UIViewController) -> Bool {
      guard _isShowing else { return false }
      guard let rootViewController = rootViewController else { fatalError() }
      guard let rootViewControllerIndex = context?.viewControllers.index(of: rootViewController) else { return true }
      guard let showingViewControllerIndex = context?.viewControllers.index(of: viewController) else { return false }
      
      return showingViewControllerIndex < rootViewControllerIndex
   }
}
