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
        DeviceListView()
            .environmentObject(watchManager)
    }
}

#Preview {
    ContentView()
}
