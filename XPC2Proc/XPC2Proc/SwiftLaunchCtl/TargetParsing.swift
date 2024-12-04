//
//  TargetParsing.swift
//  XPC2Program
//
//  Created by Brandon Dalton on 11/28/24.
//

import Foundation


struct Service {
    let handle: Int?
    let name: String
}

struct ProgramTarget {
    let path: String
    let pid: Int?
}

struct Endpoint {
    let name: String
    let port: String
}

struct ServiceTarget {
    let service: Service
    let programPath: String
    let endpoints: [Endpoint]
}



/// Attempts to return the `pid =` field from a service target `print` operation
func parsePID(from serviceTargetPrintInfo: String) -> Int? {
    let scanner = Scanner(string: serviceTargetPrintInfo)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines
    
    let pidIdentifier = "pid ="
    scanner.currentIndex = serviceTargetPrintInfo.startIndex
    if let _ = scanner.scanUpToString(pidIdentifier), scanner.scanString(pidIdentifier) != nil {
        if let pid = scanner.scanUpToCharacters(from: .whitespacesAndNewlines)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return Int(pid)
        }
    }
    
    return nil
}

/// Attempts to return the program path `program =`, `originator =`, or `program identifier =` from a service target `print` operation
func parseProgramPath(from serviceTargetPrintInfo: String) -> ProgramTarget? {
    let scanner = Scanner(string: serviceTargetPrintInfo)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines
    
    // First handle the common identifiers
    let commonIdentifiers = ["program =", "originator ="]
    for identifier in commonIdentifiers {
        scanner.currentIndex = serviceTargetPrintInfo.startIndex
        if let _ = scanner.scanUpToString(identifier), scanner.scanString(identifier) != nil {
            if let programPath = scanner.scanUpToCharacters(from: .newlines)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return ProgramTarget(path: programPath, pid: nil)
            }
        }
    }
    
    // Last ditch effort -- for USER --> GUI --> PID
    let pidCase = "program identifier ="
    scanner.currentIndex = serviceTargetPrintInfo.startIndex
    if let _ = scanner.scanUpToString(pidCase), scanner.scanString(pidCase) != nil {
        if let programPath = scanner.scanUpToCharacters(from: .newlines)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let endIndex = programPath.range(of: " (")?.lowerBound {
                /// Now we have the stem like: `Contents/Resources/SampleLaunchAgent`.
                /// We need to now get the PID and query it's target: `pid/<pid>`
                let programPath = String(programPath[..<endIndex])
                let pid = parsePID(from: serviceTargetPrintInfo)
                
                // Now since we're returning a pid as well our caller should lookup that handle's path
                return ProgramTarget(path: programPath, pid: pid)
            }
        }
    }
    
    return nil
}

/// Given output from a domain target print operation attempt to return the hosted `launchd` services.
func parseServices(from input: String) -> [Service] {
    var services: [Service] = []

    let scanner = Scanner(string: input)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines

    while !scanner.isAtEnd {
        if scanner.scanUpToString("services =") != nil, scanner.scanString("services =") != nil {
            _ = scanner.scanString("{")
            
            while true {
                // Attempt to scan a handle (the service number)
                if let handle = scanner.scanInt() {
                    // Skip any intermediary value(s) and '-'
                    while scanner.scanInt() != nil {
                        // Continue scanning until we don't have an integer, which could be the intermediary value.
                    }
                    _ = scanner.scanString("-")
                    
                    // Attempt to scan the name
                    let serviceName = scanner.scanUpToCharacters(from: .newlines)
                    
                    if var name = serviceName?.trimmingCharacters(in: .whitespaces) {
                        // Remove additional descriptors (e.g., "(pe)")
                        if let descriptorRange = name.range(of: "\\(.*?\\)", options: .regularExpression) {
                            name.removeSubrange(descriptorRange)
                            name = name.trimmingCharacters(in: .whitespaces)
                        }

                        services.append(Service(handle: handle, name: name))
                    }
                } else {
                    break
                }
            }
        } else {
            // There were no services found...
            break
        }
    }
    
    return services
}

/// Given output from a service target print operation attempt to return the advertised Mach services (Endpoints).
/// Endpoints contain a `name` and a `port`.
func parseEndpoints(from input: String) -> [Endpoint] {
    var endpoints: [Endpoint] = []

    let scanner = Scanner(string: input)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines
    
    let endpointSectionMarker = "endpoints = {"
    scanner.currentIndex = input.startIndex
    guard let _ = scanner.scanUpToString(endpointSectionMarker),
          scanner.scanString(endpointSectionMarker) != nil else {
        return endpoints
    }

    while true {
        guard let endpointName = scanner.scanUpToString("=")?.trimmingCharacters(in: .whitespacesAndNewlines),
              scanner.scanString("=") != nil,
              scanner.scanString("{") != nil else {
            break
        }

        var port: String?

        // Scan properties within the current endpoint block
        while true {
            guard let key = scanner.scanUpToString("=")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  scanner.scanString("=") != nil else {
                break
            }

            if key == "port" {
                if let portValue = scanner.scanUpToCharacters(from: .whitespacesAndNewlines)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    port = portValue
                }
            }

            // Scan to the end of the current line or closing brace
            _ = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "\n}"))
            if scanner.scanString("}") != nil {
                break
            }
        }

        // If we have found a valid port, add it to the endpoints array
        if let validPort = port {
            let endpoint = Endpoint(name: endpointName.replacingOccurrences(of: "\"", with: ""), port: validPort)
            endpoints.append(endpoint)
        }

        // Look for the next endpoint or the end of the endpoints section
        if scanner.scanString("}") != nil {
            // Check if there's another endpoint
            if scanner.scanString("\"") == nil {
                break
            } else {
                scanner.currentIndex = scanner.string.index(before: scanner.currentIndex) // Rewind to parse next endpoint
            }
        }
    }

    return endpoints
}

/// Given output from a domain target attempt to return a list of the disabled `launchd` services.
func parseDisabledServices(from input: String) -> [String] {
    var services: [String] = []

    let scanner = Scanner(string: input)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines

    // Locate the "disabled services =" section
    if scanner.scanUpToString("disabled services =") != nil, scanner.scanString("disabled services =") != nil {
        if scanner.scanString("{") != nil {
            // Loop until we reach the closing brace "}"
            while !scanner.isAtEnd {
                if let serviceLabel = scanner.scanUpToString("=>")?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // Remove any surrounding quotes from the service label
                    let cleanedLabel = serviceLabel.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    services.append(cleanedLabel)
                }
                
                // Move scanner past "=> status" and go to the next line
                if scanner.scanUpToString("\n") == nil {
                    break
                }
                
                // Stop if we find the closing brace "}"
                if scanner.scanString("}") != nil {
                    break
                }
            }
        }
    }
    
    return services
}
