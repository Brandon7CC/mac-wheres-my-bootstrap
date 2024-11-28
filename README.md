# "Mac, Where's My Bootstrap?"

## Overview
The following repository contains samples for the 2024 Objective By the Sea v7.0 talk: ["Mac, Where's My Bootstrap?"](https://objectivebythesea.org/v7/talks.html#:~:text=Mac%2C%20Where%E2%80%99s%20my%20Bootstrap%3F.%20What%20is%20the%20Bootstrap%20Server%20and%20How%20Can%20You%20Talk%20To%20It%3F). Here you'll find `SwiftLaunchCtl` which enables programatic Mach service name to path resolution. 

## Mach Services vs. `launchd` Services
* **`launchd` services**: such as Launch Daemons and Agents are jobs defined in a property list to be managed by the system. These jobs are backed by a single hosting program (see the `Program` key in the `Info.plist`). These programs can host multiple Mach Services to facilitate communication.
* **Mach Services**: Low level atomic IPC channels managed / claimed by a program (see the `MachServices` / `SBMachServices` key in the `Info.plist`) 


## Usage

Running main.swift will execute an ES client to auto resolve service endpoints.

### Output
**SMAppService** example: `com.xpc.example.agent.hello`
```json
{"id":"5C57EA67-91BB-407D-8466-9CCFDAD065F5","programPath":"/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.apple.TextInputUI.xpc.CursorUIViewService"}
{"id":"8C569FE0-6DF8-4154-BCB5-92F1962C2D2F","programPath":"/usr/sbin/cfprefsd","xpcDomain":{"system":{}},"xpcServiceName":"com.apple.cfprefsd.daemon"}
{"id":"ED20CC35-D012-48C8-AFF8-7F5E20EE2A31","programPath":"/Users/pegasus/Downloads/SMAppServiceSampleCode.app/Contents/Resources/SampleLaunchAgent","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.xpc.example.agent.hello"}
{"id":"98D6EC49-5006-4E26-8248-0A9453052F28","programPath":"/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.apple.TextInputUI.xpc.CursorUIViewService"}
```

**Microsoft Teams** example: `com.microsoft.teams2.notificationcenter`
```json
{"id":"7C484C9A-92C9-4213-AC9B-D3A96AFF0CA4","programPath":"/System/Library/PrivateFrameworks/TCC.framework/Support/tccd","xpcDomain":{"system":{}},"xpcServiceName":"com.apple.tccd.system"}
{"id":"76598196-F791-4525-8379-6106E5B07B07","programPath":"/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/XPCServices/com.apple.hiservices-xpcservice.xpc/Contents/MacOS/com.apple.hiservices-xpcservice","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.apple.hiservices-xpcservice"}
{"id":"30FDE1B6-2343-4F3B-AB7E-D16358723970","programPath":"/usr/libexec/runningboardd","xpcDomain":{"system":{}},"xpcServiceName":"com.apple.runningboard"}
{"id":"490E7007-281D-490A-BF4A-E02677DBAF8A","programPath":"/Applications/Microsoft Teams.app/Contents/XPCServices/com.microsoft.teams2.notificationcenter.xpc","xpcDomain":{"pid":{"_0":11009}},"xpcServiceName":"com.microsoft.teams2.notificationcenter"}

```

### Query launchd
```swift
let launchCtl = LaunchCtl()
//
//// XPC (Mach) service name to program path
let xpcServiceName: String = "com.apple.dt.Xcode.DeveloperSystemPolicyService"
//// The domain it's in
let domain: Domain = Domain.pid(16764)
//
//// Let's do our magic!
let resolvedProgramPath = launchCtl.resolveProgramPath(
    from: xpcServiceName,
    in: domain
)

print("\(xpcServiceName) ==> \(resolvedProgramPath)")
```

```swift
//// System domain service target example
//if let response = launchCtl.executeLaunchdRequest(domain: .system, operation: .printServiceTarget(serviceName: "com.apple.accessoryupdaterd")) {
//    print(response)
//}
//
//// Per-pid domain service target example
if let response = launchCtl.executeLaunchdRequest(
    domain: .pid(34496),
    operation: .printServiceTarget(serviceName: "com.microsoft.teams2.notificationcenter")
) {
    print(response)
}
```

```swift
// Explicit usage -- research use-cases
// User domain target example
//
// type: The domain we’re targeting. 1=system, 2=user, 3=login, 5=pid, 8=gui
// handle: For system/user/gui domains use the UID (e.g. 501), for login use the ASID, for pid use the pid.
// subsystem: 2=print service target info, 3=print domain target info
// routine: 708=print a service target, 828=print a domain target
// and name: The service name if service target (subsystem == 2 && routine == 708)
if let response = launchCtl.executeLaunchdRequest(handle: 100016, type: 1, routine: 828, subsystem: 3, name: "com.apple.accessoryupdaterd") {
    print("Service Response (explicit parameters): \(response)")
}
```
