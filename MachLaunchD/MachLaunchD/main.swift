//
//  main.swift
//  MachLaunchD
//
//  Created by Brandon Dalton on 9/8/24.
//

import Foundation

let serviceName = "com.apple.tccd"
var program_path: String?

let swiftLaunchCtl = SwiftLaunchCtl()
if let path = swiftLaunchCtl.machEndpointToPath(machEndpointName: serviceName) {
    program_path = path
    print(path)
}


