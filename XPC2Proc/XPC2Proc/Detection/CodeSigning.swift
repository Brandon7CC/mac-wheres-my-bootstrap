//
//  CodeSigning.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 12/1/24.
//

import Foundation
import Security

/// Given the path to a bundle on the file system attempt to resolve the executable path
///
func resolveExecutablePath(fromPath path: String) -> String? {
    let fileManager = FileManager.default
    
    if fileManager.fileExists(atPath: path) {
        if let bundle = Bundle(path: path),
           let bundleExecutable = bundle.executablePath {
            return bundleExecutable
        }
        return path
    }
    return nil
}


func getTeamID(for processPath: String, retried: Bool = false) throws -> String {
    /// First try to resolve the executable path
    guard let resolvedPath = resolveExecutablePath(fromPath: processPath) else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecParam), userInfo: [
            NSLocalizedDescriptionKey: "Invalid or nonexistent path: \(processPath)"
        ])
    }
    
    let executableURL = URL(fileURLWithPath: resolvedPath)
    
    /// Create a reference to our static code to pull signing information
    var staticCode: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode)
    guard status == errSecSuccess, let staticCode = staticCode else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "Failed to create SecStaticCode object."
        ])
    }
    
    /// Pull the signing information from the executable
    var signingInfo: CFDictionary?
    let signingStatus = SecCodeCopySigningInformation(
        staticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &signingInfo
    )
    guard signingStatus == errSecSuccess, let info = signingInfo as? [String: Any] else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(signingStatus), userInfo: [
            NSLocalizedDescriptionKey: "Failed to copy signing information."
        ])
    }

    /// Method 1: Extract from TeamIdentifier key directly
    /// Pull the team ID from: `kSecCodeInfoTeamIdentifier`
    if let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String {
        return teamID
    }
    
    /// Method 2: Extract from `entitlements-dict`
    if let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
       let teamID = entitlements["com.apple.developer.team-identifier"] as? String {
        return teamID
    }

    /// Method 3: Parse from designated requirement
    var requirement: SecRequirement?
    let requirementStatus = SecCodeCopyDesignatedRequirement(staticCode, [], &requirement)

    if requirementStatus == errSecSuccess, let requirement = requirement {
        let requirementString = String(describing: requirement)
        if let teamIDRange = requirementString.range(of: "identifier \""),
           let teamID = requirementString[teamIDRange.upperBound...].split(separator: "\"").first {
            return String(teamID)
        }
    }

    /// Method 4: Let's try to extract from the `main-executable` in code signing info (retry logic)
    /// Last ditch effort
    if !retried, let mainExecutablePath = (info[kSecCodeInfoMainExecutable as String] as? URL)?.path ?? (info[kSecCodeInfoMainExecutable as String] as? String) {
        return try getTeamID(for: mainExecutablePath, retried: true)
    }

    throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInternalError), userInfo: [
        NSLocalizedDescriptionKey: "Team ID not found in signing information."
    ])
}




/// For an executable at a given path attempt to return the code signing ID.
/// Similar to the above for Team ID -- we'll try to resolve the executable path for you.
///
func getSigningID(for processPath: String) -> String? {
    guard let resolvedPath = resolveExecutablePath(fromPath: processPath) else {
        return nil
    }
    
    let url = URL(fileURLWithPath: resolvedPath)
    
    /// Create a reference to our static code to pull signing information
    var staticCode: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
    
    /// This will mean unsigned code...
    guard status == errSecSuccess, let code = staticCode else {
//        print("Error creating static code: \(status)")
        return nil
    }

    var codeInfo: CFDictionary?
    let copyStatus = SecCodeCopySigningInformation(code, SecCSFlags(), &codeInfo)
    /// Pull the signing ID from `kSecCodeInfoIdentifier`
    guard copyStatus == errSecSuccess, let info = codeInfo as? [String: Any],
          let signingID = info[kSecCodeInfoIdentifier as String] as? String else {
//        print("Error copying signing information: \(copyStatus)")
        return nil
    }

    return signingID
}
