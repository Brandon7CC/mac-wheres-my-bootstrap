//
//  ESClient.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 11/28/24.
//


import Foundation
import EndpointSecurity


// MARK: - Event subscriptions
public var eventSubscriptions: [es_event_type_t] = [
    ES_EVENT_TYPE_NOTIFY_XPC_CONNECT
]


// MARK: - ES Process
public struct ESProcess: Identifiable, Codable {
    public var id = UUID()
    
    // Process details
    public var path, signingID, teamID: String
    public var pid: Int32
    
    init(from rawProcess: UnsafePointer<es_process_t>) {
        self.pid = audit_token_to_pid(rawProcess.pointee.audit_token)
        self.path = String(
            cString: rawProcess.pointee.executable.pointee.path.data
        )
        
        /// Pulling out the signing information
        if rawProcess.pointee.signing_id.length > 0 {
            self.signingID = String(cString: rawProcess.pointee.signing_id.data)
        } else {
            self.signingID = ""
        }
        
        if rawProcess.pointee.team_id.length > 0 {
            self.teamID = String(cString: rawProcess.pointee.team_id.data)
        } else {
            self.teamID = ""
        }
    }
    
}

// MARK: - XPC Connection Event
public struct XPCConnectEvent: Identifiable, Codable {
    public var id = UUID()
    
    // The initiating / requesting process details
    public var process: ESProcess
    
    // XPC event details
    public var xpcServiceName: String
    public var xpcDomain: Domain
    // The XPC service path
    public var programPath: String
    public var xpcSigningID: String
    public var xpcTeamID: String
    
    
    init(fromRawEvent rawEvent: UnsafePointer<es_message_t>) {
        // MARK: - Top-level `es_message_t` / `es_process_t`
        
        self.xpcServiceName = ""
        self.xpcDomain = .system
        self.programPath = ""
        self.xpcSigningID = ""
        self.xpcTeamID = ""
        
        let rawProc = rawEvent.pointee.process
        self.process = .init(from: rawProc)
        
        // MARK: - ES event switch
        switch (rawEvent.pointee.event_type) {
        case ES_EVENT_TYPE_NOTIFY_XPC_CONNECT:
            let xpcEvent = rawEvent.pointee.event.xpc_connect.pointee
            self.xpcServiceName = String(cString: xpcEvent.service_name.data)
            
            switch (xpcEvent.service_domain_type) {
            case ES_XPC_DOMAIN_TYPE_MANAGER:
                self.xpcDomain = .system
                let launchCtl = LaunchCtl()
                // Let's do our magic!
                self.programPath = launchCtl.resolveProgramPath(
                    from: self.xpcServiceName,
                    in: self.xpcDomain
                )
            case ES_XPC_DOMAIN_TYPE_SYSTEM:
                self.xpcDomain = .system
                let launchCtl = LaunchCtl()
                // Let's do our magic!
                self.programPath = launchCtl.resolveProgramPath(
                    from: self.xpcServiceName,
                    in: self.xpcDomain
                )
            case ES_XPC_DOMAIN_TYPE_USER:
                // TOOD: Should this be euid?
                let uid = UInt64(audit_token_to_ruid(rawEvent.pointee.process.pointee.audit_token))
                self.xpcDomain = .user(uid)
                let launchCtl = LaunchCtl()
                // Let's do our magic!
                self.programPath = launchCtl.resolveProgramPath(
                    from: self.xpcServiceName,
                    in: self.xpcDomain
                )
            case ES_XPC_DOMAIN_TYPE_USER_LOGIN:
                let asid = UInt64(rawEvent.pointee.process.pointee.audit_token.val.6)
                self.xpcDomain = .login(asid)
                let launchCtl = LaunchCtl()
                // Let's do our magic!
                self.programPath = launchCtl.resolveProgramPath(
                    from: self.xpcServiceName,
                    in: self.xpcDomain
                )
            case ES_XPC_DOMAIN_TYPE_GUI:
                let uid = UInt64(audit_token_to_ruid(rawEvent.pointee.process.pointee.audit_token))
                self.xpcDomain = .gui(uid)
                let launchCtl = LaunchCtl()
                // Let's do our magic!
                self.programPath = launchCtl.resolveProgramPath(
                    from: self.xpcServiceName,
                    in: self.xpcDomain
                )
            case ES_XPC_DOMAIN_TYPE_PID:
                let gid = rawEvent.pointee.process.pointee.group_id
                self.xpcDomain = .pid(UInt64(gid))
                let launchCtl = LaunchCtl()
                // Let's do our magic!
                self.programPath = launchCtl.resolveProgramPath(
                    from: self.xpcServiceName,
                    in: self.xpcDomain
                )
            default:
                break
            }
            
            if !self.programPath.isEmpty {
                self.xpcSigningID = getSigningID(for: self.programPath) ?? ""
                self.xpcTeamID = (try? getTeamID(for: self.programPath)) ?? ""
            }
            

        default:
            break
        }
    }
}


/// Reference: Based off [AtomicESClient](https://github.com/redcanaryco/mac-monitor/tree/main/AtomicESClient)
public class EndpointSecurityClientManager: NSObject {
    public var esClient: OpaquePointer?
    
    // A simple function to convert an `Encodable` event to JSON.
    public static func eventToJSON(value: Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        
        let encodedData = try? encoder.encode(value)
        return String(data: encodedData!, encoding: .utf8)!
    }
    
    public func bootupESClient(completion: @escaping (_: XPCConnectEvent) -> Void) -> OpaquePointer? {
        var client: OpaquePointer?
        
        // MARK: - New ES clients
        // Reference: https://developer.apple.com/documentation/endpointsecurity/client
        let result: es_new_client_result_t = es_new_client(&client){ _, event in
            // Here is where the ES client will "send" events to be handled by our app -- this is the "callback".
            completion(XPCConnectEvent(fromRawEvent: event))
        }
        
        // Check the result of your `es_new_client_result_t` operation. Here is where you'll run into issues like:
        // - Not having the ES entitlement signed to your app.
        // - Not running as `root`, etc.
        switch result {
        case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
            print("[ES CLIENT ERROR] There are too many Endpoint Security clients!")
            break
        case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
            print("[ES CLIENT ERROR] Failed to create new Endpoint Security client! The endpoint security entitlement is required.")
            break
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
            print("[ES CLIENT ERROR] Lacking TCC permissions!")
            break
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
            print("[ES CLIENT ERROR] Caller is not running as root!")
            break
        case ES_NEW_CLIENT_RESULT_ERR_INTERNAL:
            print("[ES CLIENT ERROR] Error communicating with ES!")
            break
        case ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT:
            print("[ES CLIENT ERROR] Incorrect arguments creating a new ES client!")
            break
        case ES_NEW_CLIENT_RESULT_SUCCESS:
            print("[ES CLIENT SUCCESS] We successfully created a new Endpoint Security client!")
            break
        default:
            print("An unknown error occured while creating a new Endpoint Security client!")
        }
        
        // Validate that we have a valid reference to a client
        if client == nil {
            log.error("[ES CLIENT ERROR] After atempting to make a new ES client we failed.")
            return nil
        }
        
        // MARK: - Event subscriptions
        // Reference: https://developer.apple.com/documentation/endpointsecurity/3228854-es_subscribe
        if es_subscribe(client!, eventSubscriptions, UInt32(eventSubscriptions.count)) != ES_RETURN_SUCCESS {
            print("[ES CLIENT ERROR] Failed to subscribe to core events! \(result.rawValue)")
            es_delete_client(client)
            exit(EXIT_FAILURE)
        }
        
        self.esClient = client
        return client
    }
}
