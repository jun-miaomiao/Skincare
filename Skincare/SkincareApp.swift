//
//  SkincareApp.swift
//  Skincare
//
//  Created by 林正倫 on 2026/9/1.
//

import SwiftData
import SwiftUI

@main
struct SkincareApp: App {
    init() {
        // 背景預載成分雜湊字典；內部會依 databaseVersion／JSON 雜湊決定是否強制重載
        IngredientDatabaseManager.shared.preload()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(SubscriptionStore.shared)
        }
        .modelContainer(SkincareModelContainer.shared)
    }
}
