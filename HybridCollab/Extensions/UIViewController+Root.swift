//
//  UIViewController+Root.swift
//  ARCollab
//
//  Created by Rahul on 2/7/25.
//

import UIKit

extension UIViewController {
    static var rootViewController: UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.windows.first?.rootViewController
    }
}
