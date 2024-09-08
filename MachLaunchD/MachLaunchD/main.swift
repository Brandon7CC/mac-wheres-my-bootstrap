//
//  main.swift
//  MachLaunchD
//
//  Created by Brandon Dalton on 9/8/24.
//

import Foundation

service_name = String(cString: xpcConnectionEvent.service_name.data)
if initiatingProcess.code_signing_type != "Platform",
    let serviceName = service_name {
    let swiftLaunchCtl = SwiftLaunchCtl()
    if let path = swiftLaunchCtl.machEndpointToPath(machEndpointName: serviceName) {
        program_path = path
    }
}
