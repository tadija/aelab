import Foundation

public struct PluginSource: Codable, Sendable {
    public var id: String
    public var name: String
    public var filename: String
    public var language: String
}
/// Only source files explicitly referenced by configured plugins, on their configured host.
public struct PluginSources: Sendable {
    let store: ConfigStore
    let execution: HostExecution
    public init(store: ConfigStore) { self.store = store; execution = HostExecution(home: store.home) }
    private func location(_ plugin: Plugin) throws -> (String, String) {
        for path in [plugin.source, plugin.executable].compactMap({ $0 }) + plugin.arguments {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            if path.hasPrefix("/"), let language = ["sh":"bash", "bash":"bash", "rb":"ruby", "swift":"swift"][ext] {
                try absolutePath(path); return (path, language)
            }
        }
        throw AEError("Plugin has no configured editable Bash, Ruby or Swift source")
    }
    private func source(host: String, id: String) async throws -> (Host, String, String) {
        let config = try await store.read().config; let host = try config.host(host)
        guard let definition = config.plugins.first(where: { $0.id == id }) else { throw AEError("Unknown plugin") }
        let plugin = try await definition.resolved(on: host, execution: execution)
        let (path, language) = try location(plugin)
        return (host, path, language)
    }
    public func list(host id: String) async throws -> [PluginSource] {
        let config = try await store.read().config; let host = try config.host(id)
        let home = config.plugins.contains(where: { $0.needsHome(on: host) }) ? try await HostFiles(execution: execution).home(host) : "/"
        var result: [PluginSource] = []
        for definition in config.plugins {
            let plugin = try definition.resolved(home: home, remote: !host.isLocal)
            guard let (path, language) = try? location(plugin) else { continue }
            let check = try await execution.execute(host, script: "test -f " + quote(path) + " && test ! -L " + quote(path) + " && test -r " + quote(path), timeout: 5)
            if check.status == 0 { result.append(PluginSource(id: plugin.id, name: plugin.name, filename: URL(fileURLWithPath: path).lastPathComponent, language: language)) }
        }
        return result.sorted { $0.filename < $1.filename }
    }
    public func read(host id: String, plugin: String) async throws -> ConfigDocument {
        let (host, path, _) = try await source(host: id, id: plugin)
        let script = "set -eu\np=" + quote(path) + "\ntest -f \"$p\"\ntest ! -L \"$p\"\ntest -r \"$p\"\nhead -c 65537 \"$p\" | base64"
        let result = try await execution.execute(host, script: script, timeout: 5)
        guard result.status == 0, !result.truncated, let data = Data(base64Encoded: result.output.filter { !$0.isWhitespace }), data.count <= 65_536,
              let content = String(data: data, encoding: .utf8), !content.contains("\0") else { throw AEError("Cannot read plugin source: require a readable regular UTF-8 file of at most 64 KiB") }
        return ConfigDocument(content: content, revision: revision(data))
    }
    public func edit(host id: String, plugin: String, document: ConfigDocument, save: Bool) async throws -> ConfigDocument {
        let (host, path, language) = try await source(host: id, id: plugin)
        let data = Data(document.content.utf8)
        guard data.count <= 65_536, !document.content.contains("\0") else { throw AEError("Plugin source must be UTF-8 text of at most 64 KiB") }
        let original = try await read(host: id, plugin: plugin)
        if save, original.revision != document.revision { throw RevisionConflict("Plugin source changed; reload before saving") }
        let ext = language == "bash" ? "sh" : language == "ruby" ? "rb" : "swift"
        let syntax = language == "bash" ? "/bin/bash -n" : language == "ruby" ? "ruby -c" : "swiftc -frontend -parse"
        let folder = save ? URL(fileURLWithPath: path).deletingLastPathComponent().path : "/tmp"
        // A private sibling directory keeps rename atomic; the fixed lock serializes aelab writers.
        var script = "set -eu\numask 077\np=" + quote(path) + "\n"
        if save { script += "lock=\"$p.aelab-edit-lock\"\nmkdir \"$lock\" || { echo 'Source is being edited; retry' >&2; exit 1; }\ntrap 'rmdir \"$lock\"' EXIT\n" }
        script += "work=$(mktemp -d " + quote(folder + "/.aelab-edit.XXXXXX") + ")\n"
        script += save ? "trap 'rm -rf \"$work\"; rmdir \"$lock\"' EXIT HUP INT TERM\n" : "trap 'rm -rf \"$work\"' EXIT HUP INT TERM\n"
        script += "test -f \"$p\"\ntest ! -L \"$p\"\n"
        if save {
            script += "cp -p \"$p\" \"$work/original\"\n"
            script += "if command -v sha256sum >/dev/null 2>&1; then digest=$(sha256sum \"$work/original\"); else digest=$(shasum -a 256 \"$work/original\"); fi\ndigest=${digest%% *}\n"
            script += "test \"$digest\" = " + quote(original.revision) + " || { echo 'Plugin source changed; reload before saving' >&2; exit 73; }\n"
            script += "cp -p \"$work/original\" \"$work/new." + ext + "\"\n"
        }
        script += "printf '%s' " + quote(data.base64EncodedString()) + " | base64 -d > \"$work/new." + ext + "\"\n" + syntax + " \"$work/new." + ext + "\"\n"
        if save {
            script += "test ! -L \"$p\" && cmp -s \"$p\" \"$work/original\" || { echo 'Plugin source changed; reload before saving' >&2; exit 73; }\nmv -f \"$work/new." + ext + "\" \"$p\"\n"
        }
        try await store.audit(save ? "plugin-source-save" : "plugin-source-validate", host: id, target: plugin, outcome: "requested")
        let result = try await execution.execute(host, script: script, timeout: 15)
        if result.status == 73 { throw RevisionConflict("Plugin source changed; reload before saving") }
        guard result.status == 0 else { throw AEError("Plugin source validation/save failed: " + result.error + result.output) }
        try await store.audit(save ? "plugin-source-save" : "plugin-source-validate", host: id, target: plugin, outcome: "ok")
        return ConfigDocument(content: document.content, revision: revision(data))
    }
}

public struct PluginDeployment: Codable, Sendable {
    public var sourceHost: String
    public var targetHost: String
    public var plugin: String
    public var filename: String
    public var sourcePath: String
    public var targetPath: String
    public var configurationRevision: String
    public var sourceRevision: String
    public var targetRevision: String?
    public var requiresBuild: Bool
}
extension PluginSources {
    private func targetRevision(host: Host, path: String) async throws -> String? {
        let script = "p=" + quote(path) + "; test ! -L \"$p\" || exit 1; if test -e \"$p\"; then test -f \"$p\" && test -r \"$p\" || exit 1; head -c 65537 \"$p\" | base64; else printf '%s' '-'; fi"
        let result = try await execution.execute(host, script: script, timeout: 5)
        guard result.status == 0, !result.truncated else { throw AEError("Target must be absent or a readable regular source file") }
        if result.output == "-" { return nil }
        guard let data = Data(base64Encoded: result.output.filter { !$0.isWhitespace }), data.count <= 65_536 else { throw AEError("Target source exceeds 64 KiB") }
        return revision(data)
    }
    public func deployment(host id: String, plugin: String, from sourceID: String) async throws -> PluginDeployment {
        let snapshot = try await store.read(); let local = try snapshot.config.host(sourceID); let target = try snapshot.config.host(id)
        guard local.isLocal, !target.isLocal else { throw AEError("Deploy scripts from an explicit local host to an SSH host") }
        let (_, sourcePath, _) = try await source(host: sourceID, id: plugin)
        let (_, targetPath, _) = try await source(host: id, id: plugin)
        let document = try await read(host: sourceID, plugin: plugin)
        guard let definition = snapshot.config.plugins.first(where: { $0.id == plugin }) else { throw AEError("Unknown plugin") }
        let executable = try await definition.resolved(on: local, execution: execution).executable
        let isScript = ["sh", "bash", "rb", "swift"].contains(URL(fileURLWithPath: executable).pathExtension)
        let interpreted = ["bash", "sh", "ruby", "swift"].contains(URL(fileURLWithPath: executable).lastPathComponent)
        return PluginDeployment(sourceHost: sourceID, targetHost: id, plugin: plugin, filename: URL(fileURLWithPath: sourcePath).lastPathComponent,
                                sourcePath: sourcePath, targetPath: targetPath, configurationRevision: snapshot.revision, sourceRevision: document.revision,
                                targetRevision: try await targetRevision(host: target, path: targetPath), requiresBuild: !isScript && !interpreted)
    }
    public func deploy(host id: String, plugin: String, plan: PluginDeployment) async throws -> ConfigDocument {
        guard plan.targetHost == id, plan.plugin == plugin else { throw AEError("Deployment host/plugin mismatch") }
        let current = try await deployment(host: id, plugin: plugin, from: plan.sourceHost)
        guard current.configurationRevision == plan.configurationRevision, current.sourceRevision == plan.sourceRevision,
              current.targetRevision == plan.targetRevision, current.sourcePath == plan.sourcePath, current.targetPath == plan.targetPath else { throw RevisionConflict("Script or configuration changed; reload the deployment preview") }
        let document = try await read(host: current.sourceHost, plugin: plugin)
        guard document.revision == plan.sourceRevision else { throw RevisionConflict("Local script changed; reload the deployment preview") }
        let target = try await store.read().config.host(id)
        let folder = URL(fileURLWithPath: current.targetPath).deletingLastPathComponent().path
        var script = "set -eu\numask 077\np=" + quote(current.targetPath) + "\nmkdir -p " + quote(folder) + "\nlock=\"$p.aelab-edit-lock\"\nmkdir \"$lock\"\ntrap 'rmdir \"$lock\"' EXIT\nwork=$(mktemp -d " + quote(folder + "/.aelab-deploy.XXXXXX") + ")\ntrap 'rm -rf \"$work\"; rmdir \"$lock\"' EXIT HUP INT TERM\n"
        script += "test ! -L \"$p\" || { echo 'Target is a symlink' >&2; exit 73; }\n"
        if let expected = current.targetRevision {
            script += "test -f \"$p\" || exit 73\ncp -p \"$p\" \"$work/original\"\nif command -v sha256sum >/dev/null 2>&1; then digest=$(sha256sum \"$work/original\"); else digest=$(shasum -a 256 \"$work/original\"); fi\ndigest=${digest%% *}\ntest \"$digest\" = " + quote(expected) + " || exit 73\ncp -p \"$work/original\" \"$work/new\"\n"
        } else { script += "test ! -e \"$p\" || exit 73\n" }
        script += "printf '%s' " + quote(Data(document.content.utf8).base64EncodedString()) + " | base64 -d > \"$work/new\"\n"
        if current.targetRevision == nil {
            script += "chmod 700 \"$work/new\"\nln \"$work/new\" \"$p\" || exit 73\n"
        } else { script += "test ! -L \"$p\" && cmp -s \"$p\" \"$work/original\" || exit 73\nmv -f \"$work/new\" \"$p\"\n" }
        try await store.audit("plugin-deploy", host: id, target: plugin, outcome: "requested")
        let result = try await execution.execute(target, script: script, timeout: 15)
        if result.status == 73 { throw RevisionConflict("Target script changed; reload the deployment preview") }
        guard result.status == 0 else { throw AEError("Script deployment failed: " + result.error) }
        try await store.audit("plugin-deploy", host: id, target: plugin, outcome: "saved")
        return document
    }
}
