//
//  Domains.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 11/28/24.
//

import Foundation


public enum Domain: Codable {
    case system
    case user(UInt64)    // UID
    case login(UInt64)   // ASID
    case pid(UInt64)     // PID
    case gui(UInt64)     // UID

    var handle: UInt64 {
        switch self {
        case .system: return 0
        case .user(let uid): return uid
        case .login(let asid): return asid
        case .pid(let pid): return pid
        case .gui(let uid): return uid
        }
    }

    var type: UInt64 {
        switch self {
        case .system: return 1
        case .user: return 2
        case .login: return 3
        case .pid: return 5
        case .gui: return 8
        }
    }
}
