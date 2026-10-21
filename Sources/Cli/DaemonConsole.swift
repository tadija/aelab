import Core
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum DaemonConsole {
    static func run(host: Core.Host, script: String, execution: HostExecution) async throws {
        let terminal = try await execution.terminal(host, script: script)
        var original = termios(); let interactive = isatty(STDIN_FILENO) == 1 && tcgetattr(STDIN_FILENO, &original) == 0
        if interactive { var raw = original; cfmakeraw(&raw); _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw) }
        defer { if interactive { _ = tcsetattr(STDIN_FILENO, TCSANOW, &original) } }
        let input = Task.detached {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            while !Task.isCancelled {
                if poll(&descriptor, 1, 100) <= 0 { continue }
                var bytes = [UInt8](repeating: 0, count: 16384); let count = read(STDIN_FILENO, &bytes, bytes.count)
                if count <= 0 { try? await terminal.signal("EOF"); return }
                do { try await terminal.input(Data(bytes.prefix(count))) } catch { return }
            }
        }
        let resize = Task {
            var previous = ""
            while !Task.isCancelled {
                var size = winsize()
                if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 {
                    let key = "\(size.ws_col):\(size.ws_row)"
                    if key != previous { previous = key; try? await terminal.resize(cols: max(2, min(500, Int(size.ws_col))), rows: max(2, min(300, Int(size.ws_row)))) }
                }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
        while let data = await terminal.readChunk() { FileHandle.standardOutput.write(data) }
        input.cancel(); resize.cancel(); await terminal.closeSession()
    }
}
