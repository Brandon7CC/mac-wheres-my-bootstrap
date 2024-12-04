//
//  DetectionEngine.swift
//  XPC2Proc
//
//  Created by Brandon Dalton on 12/2/24.
//

import Foundation

/// Attempt to generically detect XPC logic exploits.
/// To do this we'll apply strict code signing validation to each side of the connection.
///
func detectXPCHijacking(for event: XPCConnectEvent) -> Bool {
    // XPC side
    let xpcTeamID = event.xpcTeamID
    let xpcSigningID = event.xpcSigningID
    
    // Requestor side
    let requestorTeamID = event.process.teamID
    let requestorSigningID = event.process.signingID
    
    // Ignore Apple for this detection
    if xpcSigningID.hasPrefix("com.apple") {
        return false
    }
    
    if !xpcTeamID.isEmpty {
        if xpcTeamID != requestorTeamID {
            // Emit a detection
            return true
        } else {
            // If they're signed with the same Team ID
            return false
        }
    }
    
    if !xpcSigningID.isEmpty {
        if xpcSigningID != requestorSigningID {
            // Emit a detection
            return true
        }
    }
    
    return false
}
