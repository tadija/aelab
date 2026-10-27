import Foundation
import PackagePlugin

@main struct BuildVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        // Git HEAD can change independently of package sources, including across worktrees.
        // The script preserves the generated file when metadata has not changed.
        return [.prebuildCommand(displayName: "Embed aelab version and build", executable: URL(fileURLWithPath: "/bin/sh"),
                                 arguments: [context.package.directoryURL.appendingPathComponent("Tools/build-metadata.sh").path, "--generate", context.pluginWorkDirectoryURL.path],
                                 outputFilesDirectory: context.pluginWorkDirectoryURL)]
    }
}
