import Foundation

// MARK: - CLI for Caffeinator

let version = "0.0.1-alpha"

enum Command: String {
    case on
    case off
    case status
    case watch
    case help
    case version
}

// MARK: - Main

func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    
    guard let commandStr = args.first else {
        printUsage()
        exit(0)
    }
    
    guard let command = Command(rawValue: commandStr.lowercased()) else {
        printError("Unknown command: \(commandStr)")
        printUsage()
        exit(1)
    }
    
    switch command {
    case .on:
        handleOn(args: Array(args.dropFirst()))
    case .off:
        handleOff()
    case .status:
        handleStatus()
    case .watch:
        handleWatch(args: Array(args.dropFirst()))
    case .help:
        printUsage()
    case .version:
        print("caffeinator version \(version)")
    }
}

// MARK: - Command Handlers

func handleOn(args: [String]) {
    var duration: Int? = nil
    var modes: [String] = ["-i"] // Default: idle
    
    for arg in args {
        if arg.hasPrefix("-") {
            // Mode flag
            modes.append(arg)
        } else if let parsed = parseDuration(arg) {
            duration = parsed
        }
    }
    
    // Remove default if other modes specified
    if modes.count > 1 {
        modes.removeFirst()
    }
    
    var processArgs = modes
    if let duration = duration {
        processArgs.append("-t")
        processArgs.append(String(duration))
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    process.arguments = processArgs
    
    // Handle Ctrl+C gracefully
    signal(SIGINT) { _ in
        print("\nCaffeinate stopped.")
        exit(0)
    }
    
    do {
        try process.run()
        
        if let duration = duration {
            print("Keeping Mac awake for \(formatDuration(duration))...")
        } else {
            print("Keeping Mac awake indefinitely...")
        }
        print("Press Ctrl+C to stop.")
        
        process.waitUntilExit()
        print("Caffeinate stopped.")
    } catch {
        printError("Failed to start caffeinate: \(error.localizedDescription)")
        exit(1)
    }
}

func handleOff() {
    // Kill all caffeinate processes
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    task.arguments = ["-x", "caffeinate"]
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            print("Caffeinate stopped.")
        } else {
            print("No caffeinate process running.")
        }
    } catch {
        printError("Failed to stop caffeinate: \(error.localizedDescription)")
        exit(1)
    }
}

func handleStatus() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "caffeinate"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n")
                print("Caffeinate is active (PID: \(pids.joined(separator: ", ")))")
            }
        } else {
            print("Caffeinate is not active.")
        }
    } catch {
        printError("Failed to check status: \(error.localizedDescription)")
        exit(1)
    }
}

func handleWatch(args: [String]) {
    guard let target = args.first else {
        printError("Usage: caffeinator watch <process-name|--pid PID>")
        exit(1)
    }
    
    var pid: Int32? = nil
    
    if target == "--pid" {
        guard let pidStr = args.dropFirst().first, let parsedPid = Int32(pidStr) else {
            printError("Invalid PID")
            exit(1)
        }
        pid = parsedPid
    } else {
        // Find process by name
        pid = findProcessByName(target)
    }
    
    guard let watchPid = pid else {
        printError("Process '\(target)' not found")
        exit(1)
    }
    
    print("Watching process \(target) (PID: \(watchPid))...")
    print("Mac will stay awake until the process ends.")
    print("Press Ctrl+C to stop watching.")
    
    // Start caffeinate with -w flag to watch the process
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    process.arguments = ["-i", "-w", String(watchPid)]
    
    signal(SIGINT) { _ in
        print("\nStopped watching.")
        exit(0)
    }
    
    do {
        try process.run()
        process.waitUntilExit()
        print("Process ended. Mac can now sleep.")
    } catch {
        printError("Failed to watch process: \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Helpers

func parseDuration(_ str: String) -> Int? {
    let lowercased = str.lowercased()
    
    // Try parsing formats like "2h", "30m", "1h30m", "90"
    if lowercased.hasSuffix("h") {
        if let hours = Int(lowercased.dropLast()) {
            return hours * 3600
        }
    } else if lowercased.hasSuffix("m") {
        if let minutes = Int(lowercased.dropLast()) {
            return minutes * 60
        }
    } else if lowercased.hasSuffix("s") {
        if let seconds = Int(lowercased.dropLast()) {
            return seconds
        }
    } else if let minutes = Int(lowercased) {
        // Bare number = minutes
        return minutes * 60
    }
    
    // Try parsing "1h30m" format using NSRegularExpression
    if let regex = try? NSRegularExpression(pattern: "(\\d+)h(\\d+)m", options: []),
       let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
        if let hoursRange = Range(match.range(at: 1), in: lowercased),
           let minutesRange = Range(match.range(at: 2), in: lowercased) {
            let hours = Int(lowercased[hoursRange]) ?? 0
            let minutes = Int(lowercased[minutesRange]) ?? 0
            return hours * 3600 + minutes * 60
        }
    }
    
    return nil
}

func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    
    if hours > 0 && minutes > 0 {
        return "\(hours)h \(minutes)m"
    } else if hours > 0 {
        return "\(hours) hour\(hours > 1 ? "s" : "")"
    } else {
        return "\(minutes) minute\(minutes > 1 ? "s" : "")"
    }
}

func findProcessByName(_ name: String) -> Int32? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-i", "-x", name]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let pidStr = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first,
               let pid = Int32(pidStr) {
                return pid
            }
        }
    } catch {
        // Ignore errors
    }
    
    // Try with partial match
    task.arguments = ["-i", name]
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let pidStr = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first,
               let pid = Int32(pidStr) {
                return pid
            }
        }
    } catch {
        // Ignore errors
    }
    
    return nil
}

func printUsage() {
    print("""
    Caffeinator CLI v\(version)
    
    A command-line tool to prevent your Mac from sleeping.
    
    USAGE:
        caffeinator <command> [options]
    
    COMMANDS:
        on [duration] [modes]   Keep Mac awake
        off                     Stop keeping Mac awake
        status                  Check if caffeinate is running
        watch <process>         Keep awake while process runs
        help                    Show this help message
        version                 Show version
    
    DURATION FORMATS:
        30m                     30 minutes
        2h                      2 hours
        1h30m                   1 hour 30 minutes
        90                      90 minutes (bare number)
    
    MODE FLAGS:
        -d                      Prevent display sleep
        -i                      Prevent idle sleep (default)
        -s                      Prevent system sleep (AC only)
        -m                      Prevent disk idle sleep
    
    EXAMPLES:
        caffeinator on 2h           Keep awake for 2 hours
        caffeinator on 30m -d       Keep display on for 30 minutes
        caffeinator on              Keep awake indefinitely
        caffeinator off             Stop caffeinate
        caffeinator status          Check status
        caffeinator watch docker    Watch Docker process
        caffeinator watch --pid 123 Watch process by PID
    """)
}

func printError(_ message: String) {
    FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
}

// Run main
main()
