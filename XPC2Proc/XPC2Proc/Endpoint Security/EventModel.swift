//
//  EventModel.swift
//  XPC2Proc
//
//  Created by Brandon Dalton on 12/2/24.
//

import SwiftUI

class EventViewModel: ObservableObject {
    @Published var allEvents: [XPCConnectEvent] = []
    @Published var detections: [XPCConnectEvent] = []
    @Published var filteredEvents: [XPCConnectEvent] = []
    
    @Published var isLoggingEnabled = false
    @Published var excludeApple = false
    
    func addEvent(_ event: XPCConnectEvent) {
        guard isLoggingEnabled else { return }
        DispatchQueue.main.async {
            self.allEvents.append(event)
            if detectXPCHijacking(for: event) {
                self.detections.append(event)
            }
            
            self.applyFilter()
        }
    }
    
    func clearEvents() {
        DispatchQueue.main.async {
            self.allEvents.removeAll()
            self.detections.removeAll()
            
            self.applyFilter()
        }
    }
    
    func toggleExcludeApple() {
        excludeApple.toggle()
        applyFilter()
    }
    
    private func applyFilter() {
        if excludeApple {
            filteredEvents = allEvents.filter {
                !$0.process.signingID.hasPrefix("com.apple") &&
                !$0.xpcServiceName.hasPrefix("com.apple") &&
                !$0.xpcServiceName.contains("(Apple)_OpenStep")
            }
        } else {
            filteredEvents = allEvents
        }
    }
}
