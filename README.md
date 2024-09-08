# "Mac, Where's My Bootstrap?"

## Overview
The following repository contains samples for the 2024 Objective By the Sea v7.0 talk: ["Mac, Where's My Bootstrap?"](https://objectivebythesea.org/v7/talks.html#:~:text=Mac%2C%20Where%E2%80%99s%20my%20Bootstrap%3F.%20What%20is%20the%20Bootstrap%20Server%20and%20How%20Can%20You%20Talk%20To%20It%3F). Here you'll find `SwiftLaunchCtl` which enables programatic Mach service name to path resolution. 

## Mach Services vs. `launchd` Services
* **`launchd` services**: such as Launch Daemons and Agents are jobs defined in a property list to be managed by the system. These jobs are backed by a single hosting program (see the `Program` key in the `Info.plist`). These programs can host multiple Mach Services to facilitate communication.
* **Mach Services**: Low level atomic IPC channels managed / claimed by a program (see the `MachServices` / `SBMachServices` key in the `Info.plist`) 


## Usage
```swift
let serviceName = "com.apple.tccd"
var program_path: String?

let swiftLaunchCtl = SwiftLaunchCtl()
if let path = swiftLaunchCtl.machEndpointToPath(machEndpointName: serviceName) {
    program_path = path
    print(path)
}
```
