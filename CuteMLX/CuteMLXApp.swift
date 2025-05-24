//
//  CuteMLXApp.swift
//  CuteMLX
//
//  Created by John Mai on 2025/5/24.
//

import SwiftUI

@main
struct CuteMLXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
