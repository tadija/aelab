import Foundation

public enum ServiceCommands {
    public static func arguments(_ service: Service, operation: String, dockerContext: String? = nil) throws -> [String] {
        guard ["status", "logs", "start", "stop", "restart"].contains(operation) else { throw AEError("Unsupported service action") }
        switch service.provider {
        case .systemd:
            let prefix = (service.sudo == true && !["status", "logs"].contains(operation)) ? ["sudo", "-n"] : []
            let scope = service.userUnit == true ? ["--user"] : []
            if operation == "logs" { return ["journalctl"] + scope + ["--no-pager", "-n", "200", "-u", service.target] }
            if operation == "status" { return ["systemctl"] + scope + ["--no-pager", "show", service.target, "--property=Id,LoadState,ActiveState,SubState,Result"] }
            return prefix + ["systemctl"] + scope + ["--no-ask-password", operation, "--", service.target]
        case .launchd:
            try validateLaunchdTarget(service.target)
            let prefix = service.sudo == true && !["status", "logs"].contains(operation) ? ["sudo", "-n"] : []
            if operation == "status" { return ["/bin/launchctl", "print", service.target] }
            if operation == "logs" {
                if let files = service.logFiles, !files.isEmpty {
                    for file in files { try absolutePath(file) }
                    return ["/usr/bin/tail", "-n", "200"] + files
                }
                let label = String(service.target.split(separator: "/").last!)
                return ["/usr/bin/log", "show", "--last", "1h", "--style", "compact", "--predicate", "process == \"launchd\" AND eventMessage CONTAINS[c] \"" + label + "\""]
            }
            if operation == "stop" {
                guard service.plist != nil else { throw AEError("Set the launchd plist path before stopping, so the service can be loaded again") }
                return prefix + ["/bin/launchctl", "bootout", service.target]
            }
            return prefix + ["/bin/launchctl", "kickstart"] + (operation == "restart" ? ["-k"] : []) + [service.target]
        case .docker:
            if operation == "logs" { return try dockerArguments(["logs", "--tail", "200", "--timestamps", service.target], context: dockerContext) }
            if operation == "status" { return try dockerArguments(["inspect", "--format", "{{json .State}}", service.target], context: dockerContext) }
            return try dockerArguments([operation, service.target], context: dockerContext)
        case .compose:
            guard let directory = service.directory else { throw AEError("Compose configuration unavailable: explicitly configure directory and files") }
            try absolutePath(directory)
            var args = try dockerArguments(["compose"], context: dockerContext) + [ "--project-directory", directory, "--project-name", service.target]
            for file in service.files ?? [] { args += ["-f", file] }
            if let file = service.environmentFile { args += ["--env-file", file] }
            if operation == "status" { return args + ["ps", "--all", "--format", "json"] }
            if operation == "logs" { return args + ["logs", "--no-color", "--tail", "200", "--timestamps"] }
            return args + [operation] // start never creates/rebuilds; stop never does down
        }
    }
}

extension ServiceCommands {
    public static func validateDockerContext(_ value: String) throws {
        guard !value.isEmpty, !value.hasPrefix("-"), value.utf8.count <= 256, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AEError("Invalid Docker context") }
    }
    public static func dockerArguments(_ arguments: [String], context: String?) throws -> [String] {
        if let context { try validateDockerContext(context); return ["docker", "--context", context] + arguments }
        return ["docker"] + arguments
    }
    public static func validateLaunchdTarget(_ target: String) throws {
        guard target.utf8.count <= 512, target.range(of: "^(system|(?:user|gui)/[0-9]+)/[A-Za-z0-9_][A-Za-z0-9_.:-]*$", options: .regularExpression) != nil else { throw AEError("Use a full launchd service target: system/label, user/UID/label or gui/UID/label") }
    }
    public static func script(_ service: Service, operation: String, dockerContext: String? = nil) throws -> String {
        let args = try arguments(service, operation: operation, dockerContext: dockerContext)
        guard service.provider == .launchd, !["status", "logs"].contains(operation), let plist = service.plist else { return command(args) }
        try absolutePath(plist)
        let label = String(service.target.split(separator: "/").last!)
        let domain = String(service.target.prefix(service.target.count - label.count - 1))
        let prefix = service.sudo == true ? ["sudo", "-n"] : []
        let preflight = "test -f " + quote(plist) + " && test -r " + quote(plist) + " || { echo 'Launchd plist is not readable' >&2; exit 1; }; label=$(/usr/bin/plutil -extract Label raw -o - " + quote(plist) + ") || exit 1; test \"$label\" = " + quote(label) + " || { echo 'Plist Label does not match the configured service target' >&2; exit 1; }; "
        if operation == "stop" { return preflight + "exec " + command(args) }
        return preflight + "if " + command(["/bin/launchctl", "print", service.target]) + " >/dev/null 2>&1; then exec " + command(args) + "; else " + command(prefix + ["/bin/launchctl", "bootstrap", domain, plist]) + " && exec " + command(args) + "; fi"
    }
}
/// The documented list columns describe the caller's bootstrap domain. Never infer lifecycle targets from diagnostic print output.
public enum LaunchdDiscovery {
    public static let script = #"""
    set -eu
    uid=$(/usr/bin/id -u)
    manager=$(/bin/launchctl managername)
    case "$manager" in Aqua) domain="gui/$uid";; System) domain=system;; *) domain="user/$uid";; esac
    printf '@aelab-domain:%s\n' "$domain"
    /bin/launchctl list
    """#
    public static func parse(_ output: String) -> [DiscoveryItem] {
        var lines = output.split(separator: "\n")
        guard let first = lines.first, first.hasPrefix("@aelab-domain:") else { return [] }
        let domain = String(first.dropFirst("@aelab-domain:".count)); lines.removeFirst()
        return lines.compactMap { line in
            let columns = line.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count == 3, let exitStatus = Int(columns[1]), columns[0] == "-" || Int(columns[0]) != nil else { return nil }
            let target = domain + "/" + columns[2]
            guard (try? ServiceCommands.validateLaunchdTarget(target)) != nil else { return nil }
            let running = (Int(columns[0]) ?? 0) > 0
            return DiscoveryItem(provider: .launchd, target: target, state: running ? "running" : exitStatus == 0 ? "stopped" : "failed")
        }
    }
}
extension Operations {
    func nativeServices(_ host: Host, platform: String) async throws -> (CommandResult?, CommandResult?) {
        if platform == "macos" { return (nil, try await execution.run(host, args: ["/bin/sh", "-c", LaunchdDiscovery.script])) }
        if ["linux", "wsl"].contains(platform) { return (try await execution.run(host, args: ["systemctl", "--no-pager", "--plain", "list-units", "--type=service", "--all", "--no-legend"]), nil) }
        return (nil, nil)
    }
    func runService(_ host: Host, service definition: Service, operation: String, platform: String) async throws -> CommandResult {
        if definition.provider == .launchd && platform != "macos" { throw AEError("launchd services require a macOS host") }
        if definition.provider == .systemd && !["linux", "wsl"].contains(platform) { throw AEError("systemd services require Linux; use launchd on macOS") }
        var service = definition
        if service.provider == .launchd {
            let paths = ([service.plist].compactMap { $0 } + (service.logFiles ?? []))
            if paths.contains(where: { $0.hasPrefix("~/") }) {
                let home = try await HostFiles(execution: execution).home(host)
                if let plist = service.plist { service.plist = try HostPath.resolve(plist, home: home) }
                if let files = service.logFiles { service.logFiles = try files.map { try HostPath.resolve($0, home: home) } }
            }
        }
        let script = try ServiceCommands.script(service, operation: operation, dockerContext: host.dockerContext)
        return try await execution.execute(host, script: script, timeout: ["status", "logs"].contains(operation) ? 15 : 60)
    }
}
