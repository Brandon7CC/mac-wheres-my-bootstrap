//
//  LaunchCtl.swift
//  SwiftLaunchCtl
//
//  Created by Brandon Dalton on 5/12/24.
//

import Foundation
import OSLog

/// Encapsulates functionality related to interacting with the launchctl API via libxpc.
final class SwiftLaunchCtl {

    /// Represents a launchd domain, such as "system", "user", or "gui".
    struct Domain {
        static let system = Domain(name: "system", rawValue: 0)
        static let user = Domain(name: "user", rawValue: 501)
        static let gui = Domain(name: "gui", rawValue: 501)

        /// The name of the domain.
        let name: String
        /// The raw numeric value of the domain.
        let rawValue: UInt64
    }

    /// Represents the type of service domain.
    enum ServiceDomainType: UInt64 {
        case system = 1, user = 2, login = 3, pid = 5, gui = 8

        /// Initializes a `ServiceDomainType` from a `Domain`.
        /// - Parameter domain: The `Domain` to convert.
        init?(domain: Domain) {
            switch domain.name {
            case "system": self = .system
            case "user": self = .user
            case "gui": self = .gui
            default: return nil
            }
        }
    }

    /// Represents an operation to be performed via XPC.
    enum XPCOperation: Equatable {
        /// Print all Mach services within a domain.
        case printMachServices
        /// Get information about a specific Mach service.
        case getMachServiceInfo(String)

        /// The numeric routine code for the operation.
        var routine: UInt64 {
            switch self {
            case .printMachServices: return 828
            case .getMachServiceInfo: return 708
            }
        }
    }

    /// A cache entry for Mach service information.
    struct CacheEntry {
        /// The timestamp when the cache entry was created.
        let timestamp: Date
        /// The cached Mach service information.
        let services: [MachServiceInfo]
    }

    /// The starting address of the shared memory region used for XPC communication.
    private var vmShmemMemory: vm_address_t = 0
    /// The size of the shared memory region. 1MB to start with.
    private let vmShmemSize: vm_size_t = 0x100000
    /// A cache for Mach service information, keyed by domain name.
    private var cache: [String: CacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.swiftLaunchCtl.cacheQueue")

    /// Constructs an XPC message for a given operation and domain.
    ///
    /// This function constructs an XPC message dictionary containing the necessary information to perform the specified operation within the specified domain.
    ///
    /// - Parameters:
    ///   - operation: The `XPCOperation` to perform.
    ///   - domain: The `Domain` in which to perform the operation.
    /// - Returns: The constructed XPC message.
    ///
    private func constructXpcMessage(operation: XPCOperation, domain: Domain) -> xpc_object_t {
        guard let serviceDomainType = ServiceDomainType(domain: domain) else {
            fatalError("Unsupported domain type \(domain.rawValue)")
        }

        var message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(message, "type", serviceDomainType.rawValue)
        xpc_dictionary_set_uint64(message, "handle", domain.rawValue)
        xpc_dictionary_set_uint64(message, "subsystem", operation == .printMachServices ? 3 : 2)
        xpc_dictionary_set_uint64(message, "routine", operation.routine)
        if case let .getMachServiceInfo(serviceName) = operation {
            xpc_dictionary_set_string(message, "name", serviceName)
        }

        allocateAndSetupShmem(for: &message)
        return message
    }

    /// Allocates and sets up a shared memory region for XPC communication.
    ///
    /// This function allocates a shared memory region using `vm_allocate` and sets up an XPC shared memory object (`xpc_shmem_t`) to be included in the XPC message.
    ///
    /// - Parameter message: The XPC message to which the shared memory object will be added.
    ///
    private func allocateAndSetupShmem(for message: inout xpc_object_t) {
        /// Allocate the shared memory region.
        /// `vm_allocate` is a Mach API call that allocates a region of virtual memory.
        /// `mach_task_self_` refers to the current task.
        /// The memory is allocated with `VM_FLAGS_ANYWHERE`: the kernel can choose the address.
        let kr = vm_allocate(mach_task_self_, &vmShmemMemory, vmShmemSize, VM_FLAGS_ANYWHERE)
        guard kr == KERN_SUCCESS, let shmemPointer = UnsafeMutableRawPointer(bitPattern: UInt(vmShmemMemory)) else {
            fatalError("Memory allocation failed or invalid pointer with error \(String(cString: mach_error_string(kr)))")
        }
        
        /// `xpc_shmem_create` creates an XPC object representing the shared memory.
        let shmem = xpc_shmem_create(shmemPointer, Int(vmShmemSize))
        xpc_dictionary_set_value(message, "shmem", shmem)
    }

    /// Sends an XPC message to `launchd` and returns the reply.
    ///
    /// This function sends the constructed XPC message to launchd via the bootstrap port and waits for a reply.
    ///
    /// - Parameter message: The XPC message to send.
    /// - Returns: The reply XPC message, or `nil` if an error occurred.
    ///
    private func sendXpcMessage(message: xpc_object_t) -> xpc_object_t? {
        /// Get the bootstrap port.
        /// The bootstrap port is a Mach port that allows communication with `launchd`.
        /// `mach_ports_lookup` retrieves the send rights for the given task.
        var ports: UnsafeMutablePointer<mach_port_t>?
        var portCount: mach_msg_type_number_t = 0
        let kr = mach_ports_lookup(mach_task_self_, &ports, &portCount)

        guard kr == KERN_SUCCESS, portCount > 0, let bootstrapPort = ports?[0] else {
            fatalError("Failed to lookup Mach ports or no ports found: \(String(cString: mach_error_string(kr)))")
        }

        /// Create an XPC pipe from the bootstrap port.
        /// This pipe is used to send the XPC message.
        let pipe = xpc_pipe_create_from_port(bootstrapPort, 0)

        /// Deallocate the ports memory.
        if let ports = ports {
            for i in 1..<Int(portCount) {
                mach_port_deallocate(mach_task_self_, ports[i])
            }
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: UnsafeMutableRawPointer(ports).assumingMemoryBound(to: UInt8.self)), vm_size_t(portCount) * vm_size_t(MemoryLayout<mach_port_t>.stride))
        }

        /// Send the XPC message and receive the reply.
        /// `xpc_pipe_routine` sends the message and waits for a reply.
        var reply: xpc_object_t?
        let error = xpc_pipe_routine(pipe, message, &reply)

        guard error == 0, let reply = reply else {
            fatalError("Error sending XPC message: \(String(cString: xpc_strerror(error)))")
        }
        return reply
    }



    /// Lists all launchd services within a given domain.
    ///
    /// This function uses the `printMachServices` XPC operation to retrieve a list of all launchd services within the specified domain.
    ///
    /// - Parameter domain: The `Domain` for which to list services. Defaults to `.system`.
    /// - Returns: A dictionary mapping service names to their corresponding PIDs, or an empty dictionary if an error occurred.
    ///
    public func listLaunchdServices(at domain: Domain = .system) -> [String: String] {
        let message = constructXpcMessage(operation: .printMachServices, domain: domain)
        guard let reply = sendXpcMessage(message: message) else {
            return [:]
        }
        return parseListServices(from: reply)
    }
    
    /// Retrieves information about a specific Mach service.
    ///
    /// This function uses the `getMachServiceInfo` XPC operation to retrieve information about the specified Mach service within the specified domain.
    ///
    /// - Parameters:
    ///   - serviceName: The name of the Mach service.
    ///   - domain: The `Domain` in which to search for the service. Defaults to `.system`.
    /// - Returns: A `MachServiceInfo` object containing information about the service.
    ///
    public func getMachServiceInfo(serviceName: String, domain: Domain = .system) -> MachServiceInfo? {
        var machServiceInfo = MachServiceInfo(launchdServiceLabel: serviceName)
        let message = constructXpcMessage(operation: .getMachServiceInfo(serviceName), domain: domain)
        guard let reply = sendXpcMessage(message: message) else {
            print("[ERROR] Failed to receive a reply from mach service info (XPC message)\n==> \(serviceName), \(domain)")
            return machServiceInfo
        }
        guard let responseString = getResponseFromSharedMemory(using: reply) else {
            print("[ERROR] Failed to get response from shared memory wile looking up a mach service\n\(serviceName), \(domain)")
            return machServiceInfo
        }
        let programPath = extractProgramPath(from: responseString)
        machServiceInfo.programPath = programPath
        machServiceInfo.rawMachInfo = responseString
        machServiceInfo.machServiceEndpoints = extractEndpointNames(from: responseString)
        return machServiceInfo
    }

    /// Retrieves the response string from the shared memory region.
    ///
    /// This function retrieves the response string written by `launchd` to the shared memory region. It also deallocates the shared memory region after retrieving the response.
    ///
    /// - Parameter response: The XPC reply message containing information about the shared memory region.
    /// - Returns: The response string, or `nil` if an error occurred.
    ///
    private func getResponseFromSharedMemory(using response: xpc_object_t) -> String? {
        guard xpc_get_type(response) == XPC_TYPE_DICTIONARY,
              let shmemPointer = UnsafeMutableRawPointer(bitPattern: UInt(vmShmemMemory)) else {
            return nil
        }

        /// Get the number of bytes written to the shared memory region.
        let bytesWritten = xpc_dictionary_get_uint64(response, "bytes-written")
        guard bytesWritten > 0, bytesWritten <= vmShmemSize else {
            return nil
        }

        /// Construct a Data object from the shared memory region.
        let responseData = Data(bytes: shmemPointer, count: Int(bytesWritten))
        
        /// Deallocate the shared memory region.
        /// `vm_deallocate` frees the allocated virtual memory.
        let deallocateResult = vm_deallocate(mach_task_self_, vmShmemMemory, vmShmemSize)
        guard deallocateResult == KERN_SUCCESS else {
            fatalError("Memory deallocation failed with error \(String(cString: mach_error_string(deallocateResult)))")
        }
        
        return String(data: responseData, encoding: .utf8)
    }

    /// Extracts the program path from the raw Mach service info string.
    ///
    /// - Parameter response: The raw Mach service info string.
    /// - Returns: The program path, or `nil` if it couldn't be extracted.
    ///
    private func extractProgramPath(from response: String) -> String? {
        let pattern = "^\\s*program\\s*=\\s*(.+)$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return response.split(separator: "\n").compactMap { line in
            if let match = regex?.firstMatch(in: String(line), options: [], range: NSRange(location: 0, length: line.utf8.count)),
               let range = Range(match.range(at: 1), in: line) {
                return String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }.first
    }

    /// Parses the list of launchd services from the XPC response.
    ///
    /// - Parameter response: The XPC response message.
    /// - Returns: A dictionary mapping service names to their corresponding PIDs.
    ///
    private func parseListServices(from response: xpc_object_t) -> [String: String] {
        guard let responseString = getResponseFromSharedMemory(using: response) else {
            print("[ERROR] Calling list services unable to get response string from shared memory.")
            return [:]
        }

        var services = [String: String]()
        let lines = responseString.split(separator: "\n").map(String.init)
        if let servicesStartIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "services = {" }) {
            var currentIndex = servicesStartIndex + 1
            while currentIndex < lines.count && lines[currentIndex].trimmingCharacters(in: .whitespacesAndNewlines) != "}" {
                let line = lines[currentIndex]
                let components = line.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
                if components.count >= 3 {
                    let pid = components[0]
                    let serviceName = components.dropFirst(2).joined(separator: " ")
                    services[serviceName] = pid
                }
                currentIndex += 1
            }
        }

        return services
    }
    
    /// Extracts Mach service endpoint names from the raw Mach service info string.
    ///
    /// - Parameter responseString: The raw Mach service info string.
    /// - Returns: An array of `MachEndpoint` objects representing the extracted endpoints.
    ///
    private func extractEndpointNames(from responseString: String) -> [MachEndpoint] {
        let pattern = "(endpoints|pid-local endpoints|instance-specific endpoints)\\s*=\\s*\\{(?:\\s*\"([^\"]+)\"\\s*=\\s*\\{[^{}]*\\})*\\s*\\}"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: responseString, options: [], range: NSRange(location: 0, length: responseString.utf16.count))

        var endpoints: [MachEndpoint] = []
        for match in matches {
            let typeRange = Range(match.range(at: 1), in: responseString)!
            let typeString = String(responseString[typeRange])

            let endpointType: MachEndpointType
            switch typeString {
            case "endpoints": endpointType = .STANDARD
            case "pid-local endpoints": endpointType = .PID_LOCAL
            case "instance-specific endpoints": endpointType = .INSTANCE_SPECIFIC
            default: endpointType = .STANDARD
            }

            let range = Range(match.range(at: 0), in: responseString)!
            let dictionaryString = String(responseString[range])
            let subPattern = "\"([^\"]+)\""
            let subRegex = try! NSRegularExpression(pattern: subPattern, options: [])
            let subMatches = subRegex.matches(in: dictionaryString, range: NSRange(location: 0, length: dictionaryString.utf16.count))
            for subMatch in subMatches {
                let endpointName = String(dictionaryString[Range(subMatch.range(at: 1), in: dictionaryString)!])
                endpoints.append(MachEndpoint(endpointName: endpointName, type: endpointType))
            }
        }

        return endpoints
    }

    /// Processes and retrieves Mach service information for a given domain.
    ///
    /// This function retrieves a list of Mach services for the specified domain, fetches detailed information for each service, and returns an array of `MachServiceInfo` objects.
    ///
    /// - Parameter domain: The `Domain` for which to retrieve Mach service information.
    /// - Returns: An array of `MachServiceInfo` objects representing the Mach services in the specified domain.
    ///
    private func processDomainServices(for domain: Domain) -> [MachServiceInfo] {
        let services = listLaunchdServices(at: domain)
        return services.map { service, pid in
            var machService = getMachServiceInfo(serviceName: service, domain: domain)
            if machService != nil {
                machService!.launchdPID = Int(pid)
                return machService!
            }
            return MachServiceInfo(launchdServiceLabel: "")
        }
    }

    /// Retrieves cached Mach service information for a given domain.
    ///
    /// This function checks if cached Mach service information is available for the specified domain. If so, it returns the cached information. Otherwise, it calls `processDomainServices` to retrieve the information, caches it, and returns the result.
    ///
    /// - Parameter domain: The `Domain` for which to retrieve Mach service information.
    /// - Returns: An array of `MachServiceInfo` objects representing the Mach services in the specified domain.
    ///
    private func getCachedDomainServices(for domain: Domain) -> [MachServiceInfo] {
        let cacheKey = domain.name

        return cacheQueue.sync {
            if let cacheEntry = cache[cacheKey] {
                return cacheEntry.services
            } else {
                let services = processDomainServices(for: domain)
                cache[cacheKey] = CacheEntry(timestamp: Date(), services: services)
                return services
            }
        }
    }

    /// Resolves a Mach endpoint name to its corresponding program path.
    ///
    /// This function searches for the specified Mach endpoint name in the cached Mach service information for the user, system, and GUI domains. If a match is found, it returns the program path of the corresponding service. If no match is found, it invalidates the cache, retrieves updated Mach service information, and searches again.
    ///
    /// - Parameter machEndpointName: The name of the Mach endpoint to resolve.
    /// - Returns: The program path corresponding to the specified Mach endpoint name, or `nil` if no match is found.
    ///
    public func machEndpointToPath(machEndpointName: String) -> String? {
        var userServices = getCachedDomainServices(for: Domain.user)
        var systemServices = getCachedDomainServices(for: Domain.system)
        var guiServices = getCachedDomainServices(for: Domain.gui)

        var allServices: [MachServiceInfo] = userServices + systemServices + guiServices
        var endpointOccurrences = [MachEndpoint: [MachServiceInfo]]()

        for service in allServices {
            guard let endpoints = service.machServiceEndpoints else { continue }
            for endpoint in endpoints {
                endpointOccurrences[endpoint, default: []].append(service)
            }
        }

        if let programPath = endpointOccurrences.first(where: { $0.key.endpointName == machEndpointName })?.value.first?.programPath {
            return programPath
        } else {
            cacheQueue.sync {
                cache.removeAll()
            }
            userServices = getCachedDomainServices(for: Domain.user)
            systemServices = getCachedDomainServices(for: Domain.system)
            guiServices = getCachedDomainServices(for: Domain.gui)

            allServices = userServices + systemServices + guiServices
            endpointOccurrences = [MachEndpoint: [MachServiceInfo]]()

            for service in allServices {
                guard let endpoints = service.machServiceEndpoints else { continue }
                for endpoint in endpoints {
                    endpointOccurrences[endpoint, default: []].append(service)
                }
            }

            return endpointOccurrences.first(where: { $0.key.endpointName == machEndpointName })?.value.first?.programPath
        }
    }
}
