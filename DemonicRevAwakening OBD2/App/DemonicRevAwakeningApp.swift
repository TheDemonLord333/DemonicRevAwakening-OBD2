//
//  DemonicRevAwakeningApp.swift
//  DemonicRevAwakening OBD2
//
//  Einstiegspunkt der App „Demonic RevAwakening“.
//

import SwiftUI

@main
struct DemonicRevAwakeningApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
        }
    }
}
