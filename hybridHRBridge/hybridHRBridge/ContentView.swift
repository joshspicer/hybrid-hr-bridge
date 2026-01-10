//
//  ContentView.swift
//  hybridHRBridge
//
//  Created by jospicer on 1/8/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var watchManager = WatchManager()
    
    var body: some View {
        TabView {
            DeviceListView()
                .tabItem {
                    Label("Devices", systemImage: "applewatch")
                }
                .environmentObject(watchManager)
            
            AppsView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2")
                }
                .environmentObject(watchManager)
            
            DebugView()
                .tabItem {
                    Label("Debug", systemImage: "ant")
                }
                .environmentObject(watchManager)
        }
    }
}

#Preview {
    ContentView()
}
