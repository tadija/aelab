import Core
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Only one daemon may use the same private runtime home.
final class DaemonRunLock {
    let descriptor: Int32
    init(home: URL) throws {
        let fd = open(home.appendingPathComponent("run.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw AEError("Cannot open daemon run lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { _ = close(fd); throw AEError("Daemon is already running in this home") }
        descriptor = fd
    }
    deinit { _ = close(descriptor) }
}
