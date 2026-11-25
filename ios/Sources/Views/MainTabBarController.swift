import UIKit
import SwiftUI

class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupAppearance()
    }

    private func setupTabs() {
        let cameraVC = CameraViewController()
        cameraVC.tabBarItem = UITabBarItem(
            title: "扫描",
            image: UIImage(systemName: "camera.viewfinder"),
            selectedImage: UIImage(systemName: "camera.viewfinder")
        )

        let listVC = UIHostingController(rootView: QuoteListView())
        listVC.tabBarItem = UITabBarItem(
            title: "暂存",
            image: UIImage(systemName: "tray"),
            selectedImage: UIImage(systemName: "tray.fill")
        )

        viewControllers = [cameraVC, listVC]
    }

    private func setupAppearance() {
        tabBar.tintColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        tabBar.backgroundColor = .systemBackground
    }
}