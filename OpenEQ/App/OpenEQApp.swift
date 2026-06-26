//
//  OpenEQApp.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import SwiftUI

@main
struct OpenEQApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            // Replace the New File command group
            CommandGroup(replacing: .newItem) {
                Button("Open Audio...") {
                    NotificationCenter.default.post(name: .openAudioFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            // Create a custom menu menu for Equalizer controls
            CommandMenu("Equalizer") {
                Button("Reset EQ") {
                    NotificationCenter.default.post(name: .resetEQ, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openAudioFile = Notification.Name("com.openeq.notification.openAudioFile")
    static let resetEQ = Notification.Name("com.openeq.notification.resetEQ")
}
