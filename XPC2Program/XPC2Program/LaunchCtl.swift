//
//  LaunchCtl.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 11/28/24.
//

import Foundation


final class LaunchCtl {
    enum Operation {
        case printServiceTarget(serviceName: String)
        case printDomainTarget
        
        /// MOXiI Vol 1 (pg. 439)
        /// Routines mapped to launchctl functionality
        var routine: UInt64 {
            switch self {
            case .printServiceTarget: return 708    // 0x2C4
            case .printDomainTarget: return 828     // 0x33C
            }
        }
        
        /// MOXiI Vol 1 (pg. 441)
        /// subsystems are classes of individual commands
        var subsystem: UInt64 {
            switch self {
            case .printServiceTarget: return 2  // Service control
            case .printDomainTarget: return 3   // Domain APIs
            }
        }
    }
    
    /// Default allocate 1MB of space
    private let vmShmemSize: vm_size_t = 0x100000
    private var vmShmemMemory: vm_address_t = 0
    
    /// Given a PID what's the path of the program's image?
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
    
    /// Returns the service target by a given service label alone (and no handle / pid)
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
    func resolveProgramPath(from machServiceName: String, in domain: Domain) -> String {
        // If the user is looking up in the per-pid domain. Use our shortcut.
        if case .pid = domain {
            if let domainTargetResponse = executeLaunchdRequest(
                domain: domain,
                operation: .printDomainTarget
            ) {
                let topLevelServices = parseServices(from: domainTargetResponse)
                
                /// Attempt to find a `launchd` service matching the Mach name
                /// Then if we find one we'll print the service target and try to extract the path
                if let service = topLevelServices.first(where: { $0.name == machServiceName }) {
                    if let handle = service.handle {
                        if handle != 0 {
                            if let serviceTargetResponse = executeLaunchdRequest(
                             domain: .pid(UInt64(handle)),
                             operation: .printDomainTarget
                            ) {
                                if let path = parseProgramPath(
                                    from: serviceTargetResponse
                                )?.path {
                                    return path
                                } else {
                                    return parseProgramPath(from: domainTargetResponse)?.path ?? ""
                                }
                            }
                        }
                    }
                    /// For some reason we couldn't get a service handle (pid)
                    return parseProgramPath(from: domainTargetResponse)?.path ?? ""
                } else {
                    /// For some reason there were no services in the domain or none matching the Mach service name
                    return parseProgramPath(from: domainTargetResponse)?.path ?? ""
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
                        // If we specified user then check the gui domain endpoints
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

    private func constructMessage(handle: UInt64, type: UInt64, routine: UInt64, subsystem: UInt64, name: String?) -> xpc_object_t {
        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(message, "handle", handle)
        xpc_dictionary_set_uint64(message, "type", type)
        xpc_dictionary_set_uint64(message, "routine", routine)
        xpc_dictionary_set_uint64(message, "subsystem", subsystem)
        if let name = name {
            xpc_dictionary_set_string(message, "name", name)
        }

        allocateSharedMemory(for: message)
        return message
    }

    private func allocateSharedMemory(for message: xpc_object_t) {
        let result = vm_allocate(mach_task_self_, &vmShmemMemory, vmShmemSize, VM_FLAGS_ANYWHERE)
        guard result == KERN_SUCCESS else {
            fatalError("Failed to allocate shared memory: \(String(cString: mach_error_string(result)))")
        }
        let shmem = xpc_shmem_create(UnsafeMutableRawPointer(bitPattern: UInt(vmShmemMemory))!, Int(vmShmemSize))
        xpc_dictionary_set_value(message, "shmem", shmem)
    }

    private func sendMessage(_ message: xpc_object_t) -> String? {
        var ports: UnsafeMutablePointer<mach_port_t>?
        var portCount: mach_msg_type_number_t = 0
        let result = mach_ports_lookup(mach_task_self_, &ports, &portCount)
        guard result == KERN_SUCCESS, let bootstrapPort = ports?.pointee else {
            fatalError("Failed to lookup bootstrap port: \(String(cString: mach_error_string(result)))")
        }

        let pipe = xpc_pipe_create_from_port(bootstrapPort, 0)
        var reply: xpc_object_t?
        let error = xpc_pipe_routine(pipe, message, &reply)
        guard error == 0, let response = reply else {
            log.error("Error sending message: \(String(cString: xpc_strerror(error)))")
            return nil
        }

        return parseResponse(from: response)
    }

    private func parseResponse(from reply: xpc_object_t) -> String? {
        guard let shmemPointer = UnsafeMutableRawPointer(bitPattern: UInt(vmShmemMemory)) else { return nil }
        let bytesWritten = xpc_dictionary_get_uint64(reply, "bytes-written")
        let response = String(bytes: Data(bytes: shmemPointer, count: Int(bytesWritten)), encoding: .utf8)

        vm_deallocate(mach_task_self_, vmShmemMemory, vmShmemSize)
        return response
    }
}
