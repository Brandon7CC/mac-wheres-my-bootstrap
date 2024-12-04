//
//  ConnectionsTable.swift
//  XPC2Proc
//
//  Created by Brandon Dalton on 12/4/24.
//

import Foundation
import SwiftUI

private func domainDescription(_ domain: Domain) -> String {
    switch domain {
    case .system: return "SYSTEM"
    case .user(let uid): return "USER (\(uid))"
    case .login(let asid): return "USER-LOGIN (\(asid))"
    case .gui(let uid): return "GUI (\(uid))"
    case .pid(let pid): return "PID (\(pid))"
    }
}

struct ConnectionsTable: View {
    @ObservedObject var viewModel: EventViewModel
    @State private var selectedEvent: XPCConnectEvent.ID?
    
    var body: some View {
        VStack(alignment: .leading) {
            
            Text("XPC Connection Requests")
                .font(.title2)
                .frame(alignment: .leading)

            Table(
                viewModel.filteredEvents.reversed(),
                selection: $selectedEvent
            ) {
                TableColumn("XPC Domain") { event in
                    Text(domainDescription(event.xpcDomain)).textSelection(.enabled)
                }
                TableColumn("Service Label") { event in
                    Text(event.xpcServiceName).textSelection(.enabled)
                }
                TableColumn("Service Path") { event in
                    Text(event.programPath).textSelection(.enabled)
                }
                TableColumn("Service Team ID") { event in
                    Text(event.xpcTeamID).textSelection(.enabled)
                }
                TableColumn("Service Signing ID") { event in
                    Text(event.xpcSigningID).textSelection(.enabled)
                }
                TableColumn("Req. Proc. Name") { event in
                    Text(event.process.path.components(separatedBy: "/").last ?? "Unknown").textSelection(.enabled)
                }
                TableColumn("Req. Proc. Path") { event in
                    Text(event.process.path).textSelection(.enabled)
                }
                TableColumn("Req. Proc. Team ID") { event in
                    Text(event.process.teamID).textSelection(.enabled)
                }
                TableColumn("Req. Proc. Signing ID") { event in
                    Text(event.process.signingID).textSelection(.enabled)
                }
            }
            
            Text("Detections").font(.title2)
                .frame(alignment: .leading)
            
            Table(
                viewModel.detections.reversed(),
                selection: $selectedEvent
            ) {
                TableColumn("XPC Domain") { event in
                    Text(domainDescription(event.xpcDomain)).textSelection(.enabled)
                }
                TableColumn("Service Label") { event in
                    Text(event.xpcServiceName).textSelection(.enabled)
                }
                TableColumn("Service Path") { event in
                    Text(event.programPath).textSelection(.enabled)
                }
                TableColumn("Service Team ID") { event in
                    Text(event.xpcTeamID).textSelection(.enabled)
                }
                TableColumn("Service Signing ID") { event in
                    Text(event.xpcSigningID).textSelection(.enabled)
                }
                TableColumn("Req. Proc. Name") { event in
                    Text(event.process.path.components(separatedBy: "/").last ?? "Unknown").textSelection(.enabled)
                }
                TableColumn("Req. Proc. Path") { event in
                    Text(event.process.path).textSelection(.enabled)
                }
                TableColumn("Req. Proc. Team ID") { event in
                    Text(event.process.teamID).textSelection(.enabled)
                }
                TableColumn("Req. Proc. Signing ID") { event in
                    Text(event.process.signingID).textSelection(.enabled)
                }
            }
        }
        .padding()
    }
}
