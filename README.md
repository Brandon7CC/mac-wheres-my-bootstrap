# "Mac, Where's My Bootstrap?"

## Overview
The following repository contains samples for the 2024 Objective By the Sea v7.0 talk: ["Mac, Where's My Bootstrap?"](https://objectivebythesea.org/v7/talks.html#:~:text=Mac%2C%20Where%E2%80%99s%20my%20Bootstrap%3F.%20What%20is%20the%20Bootstrap%20Server%20and%20How%20Can%20You%20Talk%20To%20It%3F) by [Brandon Dalton](https://swiftly-detecting.notion.site/) (@PartyD0lphin) and [Csaba Fitzl](https://theevilbit.github.io) (@theevilbit). 

This app demonstrates the ability to detect common classes of XPC exploits by validating code signing properties on both sides of the connection and pivoting off of macOS 14's [`XPC_CONNECT`](https://developer.apple.com/documentation/endpointsecurity/es_event_xpc_connect_t) Endpoint Security event.

Here you'll find the Xcode project XPC2Proc which will build to `XPC2Proc.app` and calls into our `LaunchCtl.swift`. This file enables programatic XPC service name to path resolution we leverage for detection:
```swift
func resolveProgramPath(from machServiceName: String, in domain: Domain) -> String
```


## App usage
1. Grab a copy from the releases page
2. Since this app leverages ES it needs to be run as root with FDA on the hosting process (e.g. `Terminal.app`): `sudo XPC2Proc.app/Contents/MacOS/XPC2Proc`
3. Optionally, you can test a detection.
    1. Switch to the build directory: `tests/build/`
    2. Compile the test with `tests/build/build.sh`
    3. Test a detection with: `./tests/bin/xpcConnTest com.xpc.example.agent.hello`


![Screenshot](https://github.com/Brandon7CC/mac-wheres-my-bootstrap/blob/main/resources/uiuxdetect.png)


---

## Programatic examples
Follow along at `XPC2Proc/XPC2Proc/SwiftLaunchCtl/entry.swift`. These examples leverage an ES client as well (from the cmdl).

### **SMAppService** example: `com.xpc.example.agent.hello`
```json
{"id":"5C57EA67-91BB-407D-8466-9CCFDAD065F5","programPath":"/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.apple.TextInputUI.xpc.CursorUIViewService"}
{"id":"8C569FE0-6DF8-4154-BCB5-92F1962C2D2F","programPath":"/usr/sbin/cfprefsd","xpcDomain":{"system":{}},"xpcServiceName":"com.apple.cfprefsd.daemon"}
{"id":"ED20CC35-D012-48C8-AFF8-7F5E20EE2A31","programPath":"/Users/pegasus/Downloads/SMAppServiceSampleCode.app/Contents/Resources/SampleLaunchAgent","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.xpc.example.agent.hello"}
{"id":"98D6EC49-5006-4E26-8248-0A9453052F28","programPath":"/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.apple.TextInputUI.xpc.CursorUIViewService"}
```

### **Microsoft Teams** example: `com.microsoft.teams2.notificationcenter`
```json
{"id":"7C484C9A-92C9-4213-AC9B-D3A96AFF0CA4","programPath":"/System/Library/PrivateFrameworks/TCC.framework/Support/tccd","xpcDomain":{"system":{}},"xpcServiceName":"com.apple.tccd.system"}
{"id":"76598196-F791-4525-8379-6106E5B07B07","programPath":"/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/XPCServices/com.apple.hiservices-xpcservice.xpc/Contents/MacOS/com.apple.hiservices-xpcservice","xpcDomain":{"user":{"_0":501}},"xpcServiceName":"com.apple.hiservices-xpcservice"}
{"id":"30FDE1B6-2343-4F3B-AB7E-D16358723970","programPath":"/usr/libexec/runningboardd","xpcDomain":{"system":{}},"xpcServiceName":"com.apple.runningboard"}
{"id":"490E7007-281D-490A-BF4A-E02677DBAF8A","programPath":"/Applications/Microsoft Teams.app/Contents/XPCServices/com.microsoft.teams2.notificationcenter.xpc","xpcDomain":{"pid":{"_0":11009}},"xpcServiceName":"com.microsoft.teams2.notificationcenter"}

```

## Mach Services vs. `launchd` Services
* **`launchd` services**: such as Launch Daemons and Agents are jobs defined in a property list to be managed by the system. These jobs are backed by a single hosting program (see the `Program` key in the `Info.plist`). These programs can host multiple Mach Services to facilitate communication.
* **Mach Services**: Low level atomic IPC channels managed / claimed by a program (see the `MachServices` / `SBMachServices` key in the `Info.plist`) 

### Query launchd
Follow along at [`XPC2Proc/XPC2Proc/SwiftLaunchCtl/entry.swift`](https://github.com/Brandon7CC/mac-wheres-my-bootstrap/blob/e83978fe6b707b669247c424878931f0d599e13f/XPC2Proc/XPC2Proc/SwiftLaunchCtl/entry.swift#L75). You'll need to modify the code like so:

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

---

## References
> Standing on the shoulders of giants

* ["MacOS and iOS Internals (MOXiI) Volume I - User Mode"](https://newosxbook.com/home.html) by Jonathan Levin
* ["Launchd: One Program to Rule them All"](https://www.youtube.com/watch?v=mLwn_TbBntI&t=1081s) / "Managing Processes with launchd" by Dave Zarzycki (author of launchd)
* ["Approaching Escape Velocity with launchd"](https://www.youtube.com/watch?v=AjjeuGZNdFI&t=1715s)
    * [Slides](https://bpb-us-e1.wpmucdn.com/sites.psu.edu/dist/4/24696/files/2016/06/psumac2016-95-Approaching-Escape-Velocity-with-Launchd.pdf)
* ["Bits of Launchd"](https://saelo.github.io/presentations/bits_of_launchd.pdf) by Samuel Groß [(@5aelo)](https://x.com/5aelo)
* ["Mach Ports"](https://docs.darlinghq.org/internals/macos-specifics/mach-ports.html) by Darling Docs
* ["Baby's first Rust with extra steps (XPC, launchd, and FFI)!"](https://dev.to/machkernel/baby-s-first-rust-with-extra-steps-xpc-launchd-and-ffi-4aeb) by [David Stancu](https://github.com/mach-kernel)
    * ["launchk: Cursive TUI that queries XPC to peek at launchd state"](https://github.com/mach-kernel/launchk) by David Stancu
* ["Getting Started with launchd for Sys Admins"](https://www.youtube.com/watch?v=nqpyk5oVzAg&t=2637s) by Matt Hansen
* [Red Canary Mac Monitor's AtomicESClient](https://github.com/redcanaryco/mac-monitor/tree/main/AtomicESClient) by [Brandon Dalton](https://swiftly-detecting.notion.site)

