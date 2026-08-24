import Foundation
import Network

/// Answers "is anything listening on that host and port right now?" in about a
/// second, so the app can say *the Mac isn't responding* without waiting on an
/// SSH connection attempt.
///
/// **Why not ICMP ping.** A real ping needs a raw socket, which iOS doesn't
/// hand out without a special entitlement. The practical equivalent is a TCP
/// connect to the port we actually care about — and it's the better test
/// anyway: it proves the SSH port is reachable, not merely that some machine
/// answered an echo request.
///
/// It also splits two failures that used to look identical to the user: *the
/// Mac is asleep* (nothing at the other end) and *the Mac is up but SSH
/// refused us* (bad credential, tmux missing, host key changed).
enum HostReachability {

    /// A TCP handshake to `host:port`, given up on after `timeout`.
    ///
    /// Never throws — an unreachable host is an answer, not an error.
    static func canReach(host: String, port: Int, timeout: Duration = .milliseconds(1500)) async -> Bool {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let gate = SingleResume()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                gate.arm(continuation) { connection.cancel() }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.finish(true)
                    case .failed, .cancelled:
                        gate.finish(false)
                    case .waiting:
                        // `.waiting` is Network.framework saying it can't get
                        // there yet — no route, host down, connection refused.
                        // It would keep retrying on its own; for a "should I
                        // even try SSH?" check that's already a no.
                        gate.finish(false)
                    case .setup, .preparing:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))

                Task {
                    try? await Task.sleep(for: timeout)
                    gate.finish(false)
                }
            }
        } onCancel: {
            gate.finish(false)
        }
    }

    /// Guarantees the continuation resumes exactly once. Three things race to
    /// finish this — the connection succeeding, it failing, and the timeout —
    /// and resuming a continuation twice is a crash, not a warning.
    private final class SingleResume: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?
        private var cleanup: (() -> Void)?

        func arm(_ continuation: CheckedContinuation<Bool, Never>, cleanup: @escaping () -> Void) {
            lock.lock()
            self.continuation = continuation
            self.cleanup = cleanup
            lock.unlock()
        }

        func finish(_ value: Bool) {
            lock.lock()
            let pending = continuation
            let teardown = cleanup
            continuation = nil
            cleanup = nil
            lock.unlock()

            teardown?()
            pending?.resume(returning: value)
        }
    }
}
