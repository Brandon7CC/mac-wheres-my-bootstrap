//
//  entry.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 11/28/24.
//



import Foundation
import OSLog

let log = Logger(subsystem: "com.swiftlydetecting.xpc2program", category: "debug")


// MARK: -- SwiftUI

/// Add incoming connection events to our tracked list
func uiLogger(xpcEvent: XPCConnectEvent, viewModel: EventViewModel) {
    viewModel.addEvent(xpcEvent) // Add the event to the ViewModel
}

/// Start the ES client
func startResolutionWithLogger(viewModel: EventViewModel) -> OpaquePointer? {
    let esClientManager = EndpointSecurityClientManager()
    let esClient = esClientManager.bootupESClient { event in
        uiLogger(xpcEvent: event, viewModel: viewModel)
    }
    
    if esClient == nil {
        log.error("[ES CLIENT ERROR] Error creating the endpoint security client!")
        exit(EXIT_FAILURE)
    }
    
    return esClient
}



// MARK: -- CMDL


func eventLogger(xpcEvent: XPCConnectEvent) {
    print(xpcEvent)
}

func bootupESClientWithLogger() -> OpaquePointer? {
    let esClientManager = EndpointSecurityClientManager()
    let esClient = esClientManager.bootupESClient(completion: eventLogger)
    
    if esClient == nil {
        log.error("[ES CLIENT ERROR] Error creating the endpoint security client!")
        exit(EXIT_FAILURE)
    }
    
    return esClient
}

func waitForExit() {
    let waitForCTRLC = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    waitForCTRLC.setEventHandler {
        exit(EXIT_SUCCESS)
    }
    
    waitForCTRLC.resume()
    dispatchMain()
}

//let esClient = bootupESClientWithLogger()
//
//// Simple `ctrl+c` to exit
//waitForExit()


//let launchCtl = LaunchCtl()
//
//// XPC (Mach) service name to program path
//let xpcServiceName: String = "com.apple.dt.Xcode.DeveloperSystemPolicyService"
//// The domain it's in
//let domain: Domain = Domain.pid(16764)
//
//// Let's do our magic!
//let resolvedProgramPath = launchCtl.resolveProgramPath(
//    from: xpcServiceName,
//    in: domain
//)
//
//print("\(xpcServiceName) ==> \(resolvedProgramPath)")

// GUI domain target example
//if let response = launchCtl.executeLaunchdRequest(
//    domain: .gui(501),
//    operation: .printDomainTarget
//) {
//    print(response)
//    let services = parseServices(from: response)
//    for service in services {
//        print("Handle: \(service.handle), Name: \(service.name)")
//    }
//}

//// System domain service target example
//if let response = launchCtl.executeLaunchdRequest(domain: .system, operation: .printServiceTarget(serviceName: "com.apple.accessoryupdaterd")) {
//    print(response)
//}
//
//// Per-pid domain service target example
//if let response = launchCtl.executeLaunchdRequest(
//    domain: .pid(34496),
//    operation: .printServiceTarget(serviceName: "com.microsoft.teams2.notificationcenter")
//) {
//    print(response)
//}
//



// Explicit usage -- research use-cases
// User domain target example
//
// type: The domain we’re targeting. 1=system, 2=user, 3=login, 5=pid, 8=gui
// handle: For system/user/gui domains use the UID (e.g. 501), for login use the ASID, for pid use the pid.
// subsystem: 2=print service target info, 3=print domain target info
// routine: 708=print a service target, 828=print a domain target
// and name: The service name if service target (subsystem == 2 && routine == 708)
//if let response = launchCtl.executeLaunchdRequest(handle: 100016, type: 1, routine: 828, subsystem: 3, name: "com.apple.accessoryupdaterd") {
//    print("Service Response (explicit parameters): \(response)")
//}
