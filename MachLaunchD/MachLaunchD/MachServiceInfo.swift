//
//  MachServiceInfo.swift
//  SwiftLaunchCtl
//
//  Created by Brandon Dalton on 5/12/24.
//

import Foundation

/// The reported endpoint types (observed) by `launchd`
///
enum MachEndpointType {
case STANDARD, PID_LOCAL, INSTANCE_SPECIFIC
}

/// A Mach endpoint name and type
///
struct MachEndpoint: Hashable {
    var endpointName: String
    var type: MachEndpointType
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(endpointName)
        hasher.combine(type)
    }
}

/// Program paths / `launchd` label mapped to Mach services
///
struct MachServiceInfo {
    var launchdServiceLabel: String
    var launchdPID: Int?
    var programPath: String?
    var rawMachInfo: String?
    var machServiceEndpoints: [MachEndpoint]?
    
    init(launchdServiceLabel: String) {
        self.launchdServiceLabel = launchdServiceLabel
    }
}
