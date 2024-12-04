//
//  ContentView.swift
//  XPC2Proc
//
//  Created by Brandon Dalton on 12/1/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EventViewModel()
    @State private var esClient: OpaquePointer?

    var body: some View {
        HStack(alignment: .center) {
            Button(!viewModel.isLoggingEnabled ? "Start Logging" : "Stop logging") {
                if esClient == nil {
                    esClient = startResolutionWithLogger(viewModel: viewModel)
                }
                viewModel.isLoggingEnabled.toggle()
            }
            
            Image(systemName: "circle.fill")
                .foregroundColor(viewModel.isLoggingEnabled ? .green : .gray)
            

            Button("Clear Events") {
                viewModel.clearEvents()
            }

            Button(viewModel.excludeApple ? "Include Apple" : "Exclude Apple") {
                viewModel.toggleExcludeApple()
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.excludeApple ? .red : .gray)
        }
        .padding(.top)
        
        ConnectionsTable(viewModel: viewModel)
    }
}
