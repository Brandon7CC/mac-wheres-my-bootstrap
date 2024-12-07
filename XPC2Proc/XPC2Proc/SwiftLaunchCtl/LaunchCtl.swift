//
//  LaunchCtl.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 11/28/24.
//

import Foundation


final class LaunchCtl {
    /// Default allocate 1MB of space
    private let vmShmemSize: vm_size_t = 0x100000
    private var vmShmemMemory: vm_address_t = 0
    
    /// There are two primary operations here we're working with. These are:
    /// - Service targets (requiring the service name) or
    /// - Domain targets (specifying a whole domain)
    ///
    /// We then specify the values for the XPC dict `launchd` expects:
    ///  - `routine`
    ///  - and `subsystem`
    ///
    enum Operation {
        case printServiceTarget(serviceName: String)
        case printDomainTarget

        case getServiceInfo
        
        /// MOXiI Vol 1 (pg. 439)
        /// Routines mapped to launchctl functionality
        var routine: UInt64 {
            switch self {
            case .printServiceTarget: return 708    // 0x2C4
            case .printDomainTarget: return 828     // 0x33C

            case .getServiceInfo: return 712     // 0x2c8
            }
        }
        
        /// MOXiI Vol 1 (pg. 441)
        /// subsystems are classes of individual commands
        var subsystem: UInt64 {
            switch self {
            case .printServiceTarget: return 2  // Service control
            case .printDomainTarget: return 3   // Domain APIs

            case .getServiceInfo: return 2  // Service control
            }
        }
    }
    
    /// Given a PID what's the path of the program's image?
    ///
    func getProgramPath(for pid: Int32) -> String? {
        let PROC_PIDPATHINFO_MAXSIZE = 4096
        var pathBuffer = [CChar](repeating: 0, count: PROC_PIDPATHINFO_MAXSIZE)
        let result = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        
        guard result > 0 else {
            return nil
        }
        
        return String(cString: pathBuffer)
    }
    
    /// Given a launchd service in a given domain return the service target information. Which includes
    /// - The service infomation
    /// - The services program path (if found)
    /// - and the Mach endpoints advertised by the service target
    ///
    func fetchServiceTarget(for service: Service, in domain: Domain) -> ServiceTarget? {
        if let response = executeLaunchdRequest(
            domain: domain,
            operation: .printServiceTarget(serviceName: service.name)
        ) {
            if let programTarget: ProgramTarget = parseProgramPath(from: response) {
                /// If our target contains a PID it means we need more info to construct the path.
                /// We'll call into `proc_pidpath`
                if let pid = programTarget.pid,
                   let programPath = getProgramPath(for: Int32(pid)) {
                    return ServiceTarget(
                        service: service,
                        programPath: programPath,
                        endpoints: parseEndpoints(from: response)
                    )
                } else {
                    return ServiceTarget(
                        service: service,
                        programPath: programTarget.path,
                        endpoints: parseEndpoints(from: response)
                    )
                }
            }
        }
        
        return nil
    }

    func fetchServiceTarget(by label: String, in domainType: UInt64) -> ServiceTarget? {
        let message = constructMessage(
            handle: 0,
            type: domainType,
            routine: Operation.getServiceInfo.routine,
            subsystem: Operation.getServiceInfo.subsystem,
            name: label
        )
        guard
        let reply = sendMessageWithoutParsing(message),
        let serviceAttributes = xpc_dictionary_get_dictionary(reply, "attrs"),
        let programPath = xpc_dictionary_get_string(serviceAttributes, "program"),
        let xpcEndpoints = xpc_dictionary_get_array(serviceAttributes, "XPCServiceEndpoints")
        else {
            return nil
        }
        var serviceEndpoints: [Endpoint] = []
        xpc_array_apply(xpcEndpoints) { _, endpoint in
            guard
            xpc_dictionary_get_bool(endpoint, "XPCServiceEndpointEvent") == false, // Skip event endpoints
            let name = xpc_dictionary_get_string(endpoint, "XPCServiceEndpointName")
            else {
                return true // Continue
            }
            let endpointName = String(cString: name)
            // The string value of the port is not exposed in the XPC dictionary.
            serviceEndpoints.append(Endpoint(name: endpointName, port: ""))
            return true // Keep iterating
        }
        return ServiceTarget(
            service: Service(handle: nil, name: label),
            programPath: String(cString: programPath),
            endpoints: serviceEndpoints
        )
    }
        
    /// Returns the service target by a given service label alone (and no handle / pid)
    ///
    func fetchServiceTarget(by label: String, in domain: Domain) -> ServiceTarget? {
        if let response = executeLaunchdRequest(
            domain: domain,
            operation: .printServiceTarget(serviceName: label)
        ) {
            return ServiceTarget(
                service: Service(handle: nil, name: label),
                programPath: parseProgramPath(from: response)?.path ?? "",
                endpoints: parseEndpoints(from: response)
            )
        }
        
        return nil
    }
    
    /// Attempts to resolve a Mach service name in a given domain to its program path.
    /// There are two primary logic branches depending on the domain specified.
    ///
    func resolveProgramPath(from machServiceName: String, in domain: Domain) -> String {
        // If the user is looking up in the per-pid domain. Use our shortcut.
        if case .pid = domain {
            if let domainTargetResponse = executeLaunchdRequest(
                domain: domain,
                operation: .printDomainTarget
            ) {
                let topLevelServices = parseServices(from: domainTargetResponse)
                
                /// We'll need to look through each service's endpoints
                for service in topLevelServices {
                    if let serviceTarget = fetchServiceTarget(for: service, in: domain) {
                        if serviceTarget.endpoints.contains(where: { $0.name == machServiceName }) == true {
                            return serviceTarget.programPath
                        }
                    }
                }
            }
        } else {
            if let response = executeLaunchdRequest(
                domain: domain,
                operation: .printDomainTarget
            ) {
                let topLevelServices = parseServices(from: response)
                for service in topLevelServices {
                    if let serviceTarget = fetchServiceTarget(for: service, in: domain) {
                        if serviceTarget.endpoints.contains(where: { $0.name == machServiceName }) == true {
                            return serviceTarget.programPath
                        }
                    }
                }
                
                // Last effort... for each disabled service
                let disabledServices = parseDisabledServices(from: response)
                for disabledServiceLabel in disabledServices {
                    switch domain {
                    case .system:       // Specified system domain
                        log.debug(
                            "Fetching system/\(disabledServiceLabel)\n"
                        )
                        if let systemServiceTarget = fetchServiceTarget(
                            for: Service(handle: nil, name: disabledServiceLabel),
                            in: .system
                        ) {
                            for machEndpoint in systemServiceTarget.endpoints {
                                log.debug(
                                    "Endpoint: \(machEndpoint.name)"
                                )
                            }
                            if systemServiceTarget.endpoints.contains(where: { $0.name == machServiceName }) == true {
                                return "\(systemServiceTarget.programPath)"
                            }
                        }
                        break
                    case .user:         // Specified user domain
                        // If we specified user then check the subdomains (e.g. gui)
                        log.debug(
                            "Fetching gui/\(domain.handle)/\(disabledServiceLabel)\n"
                        )
                        if let guiServiceTarget = fetchServiceTarget(
                            for: Service(handle: nil, name: disabledServiceLabel),
                            in: .gui(domain.handle)
                        ) {
                            if guiServiceTarget.endpoints.contains(where: { $0.name == machServiceName }) == true {
                                return guiServiceTarget.programPath
                            }
                        }
                        break
                    default:
                        break
                    }
                }
            }
        }
        
        return "" // No path found :(
    }

    /// Executes a launchd request based on specified domain and operation.
    ///
    func executeLaunchdRequest(domain: Domain, operation: Operation) -> String? {
        let message = constructMessage(
            handle: domain.handle,
            type: domain.type,
            routine: operation.routine,
            subsystem: operation.subsystem,
            name: {
                if case let .printServiceTarget(serviceName) = operation {
                    return serviceName
                }
                return nil
            }()
        )
        return sendMessage(message)
    }

    /// Overload: Executes a launchd request based on explicit parameters.
    ///
    func executeLaunchdRequest(handle: UInt64, type: UInt64, routine: UInt64, subsystem: UInt64, name: String?) -> String? {
        let message = constructMessage(
            handle: handle,
            type: type,
            routine: routine,
            subsystem: subsystem,
            name: name
        )
        return sendMessage(message)
    }
    
    /// Constructs our XPC dictionary message (see slide 25 of our talk or table 13-17 from MOXiI Vol 1)
    /// `type`: The domain we're targeting
    /// `handle`: UID, ASID, or PID
    /// `subsystem`: Service / domain targets
    /// `routine`: The specific operation like `print` for service target / domain target
    /// `name`: Optional depending on if we're working with a service target.
    ///
    private func constructMessage(handle: UInt64, type: UInt64, routine: UInt64, subsystem: UInt64, name: String?, withShmem: Bool = true) -> xpc_object_t {
        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(message, "type", type)
        xpc_dictionary_set_uint64(message, "handle", handle)
        xpc_dictionary_set_uint64(message, "subsystem", subsystem)
        xpc_dictionary_set_uint64(message, "routine", routine)
        if let name = name {
            xpc_dictionary_set_string(message, "name", name)
        }
        if withShmem {
            allocateSharedMemory(for: message)
        }
        return message
    }
    
    
    /// We need to allocate a shared memory region for `launchd` to write our response.
    ///
    private func allocateSharedMemory(for message: xpc_object_t) {
        let result = vm_allocate(mach_task_self_, &vmShmemMemory, vmShmemSize, VM_FLAGS_ANYWHERE)
        guard result == KERN_SUCCESS else {
            fatalError("Failed to allocate the shared memory region: \(String(cString: mach_error_string(result)))")
        }
        let shmem = xpc_shmem_create(UnsafeMutableRawPointer(bitPattern: UInt(vmShmemMemory))!, Int(vmShmemSize))
        xpc_dictionary_set_value(message, "shmem", shmem)
    }

    private func sendMessage(_ message: xpc_object_t) -> String? {
        let pipe = xpc_pipe_create_from_port(bootstrap_port, 0)
        var reply: xpc_object_t?
        let error = xpc_pipe_routine(pipe, message, &reply)
        
        guard error == 0, let response = reply else {
            log.error("Error sending XPC message: \(String(cString: xpc_strerror(error)))")
            return nil
        }
        
        return parseResponse(from: response)
    }
    
    private func sendMessageWithoutParsing(_ message: xpc_object_t) -> xpc_object_t? {
        let pipe = xpc_pipe_create_from_port(bootstrap_port, 0)
        var reply: xpc_object_t?
        let error = xpc_pipe_routine(pipe, message, &reply)
        
        guard error == 0, let response = reply else {
            log.error("Error sending XPC message: \(String(cString: xpc_strerror(error)))")
            return nil
        }
        
        return response
    }


    private func parseResponse(from reply: xpc_object_t) -> String? {
        guard let shmemPointer = UnsafeMutableRawPointer(bitPattern: UInt(vmShmemMemory)) else { return nil }
        let bytesWritten = xpc_dictionary_get_uint64(reply, "bytes-written")
        let response = String(bytes: Data(bytes: shmemPointer, count: Int(bytesWritten)), encoding: .utf8)

        vm_deallocate(mach_task_self_, vmShmemMemory, vmShmemSize)
        return response
    }
}
