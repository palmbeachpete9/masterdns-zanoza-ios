import Foundation
import Network

public enum ProfilePingResult: Equatable {
    case success(Int)
    case failure(String)
}

// Measures profile reachability by sending one UDP DNS A-query for the
// profile's delegated domain to a well-known public resolver (1.1.1.1) and
// timing the round-trip. Any response (even NXDOMAIN) counts as success.
//
// The NWConnection is configured to avoid any third-party NetworkExtension
// (interface type .other) — without this, when Happ / Shadowrocket are
// active, the ping packet gets captured and looped back to Zanoza's own
// SOCKS5 listener, which can't tunnel a DNS query in time.
public final class ProfilePinger: @unchecked Sendable {
    public static let defaultTimeout: TimeInterval = 3.0
    public static let defaultResolverHost = "1.1.1.1"
    public static let defaultResolverPort: UInt16 = 53

    public init() {}

    public func ping(_ profile: ConnectionProfile, timeout: TimeInterval = ProfilePinger.defaultTimeout) async -> ProfilePingResult {
        let domain = profile.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty, domain.contains(".") else {
            return .failure(AppLocalization.string("Domain must be a delegated subdomain (e.g. v.example.com)."))
        }
        return await Self.pingDNS(
            domain: domain,
            resolverHost: Self.defaultResolverHost,
            resolverPort: Self.defaultResolverPort,
            timeout: timeout
        )
    }

    static func pingDNS(
        domain: String,
        resolverHost: String,
        resolverPort: UInt16,
        timeout: TimeInterval
    ) async -> ProfilePingResult {
        let port = NWEndpoint.Port(rawValue: resolverPort) ?? .init(integerLiteral: 53)
        let endpoint = NWEndpoint.hostPort(host: .init(resolverHost), port: port)

        // NWParameters tweaks: prohibit `.other` (every NEPacketTunnelProvider
        // shows up as `.other`), forbid the proxied path, and prefer the
        // active physical interface explicitly if one is present.
        let parameters = NWParameters.udp
        parameters.prohibitedInterfaceTypes = [.other]
        parameters.prohibitExpensivePaths = false
        if #available(iOS 16.0, *) {
            parameters.prohibitConstrainedPaths = false
        }

        let connection = NWConnection(to: endpoint, using: parameters)
        let queue = DispatchQueue(label: "io.zanoza.pinger")
        let query = makeDnsQuery(for: domain)
        let start = DispatchTime.now()

        return await withCheckedContinuation { continuation in
            let state = PingContinuationState(continuation: continuation)

            queue.asyncAfter(deadline: .now() + timeout) {
                state.finish(.failure(AppLocalization.string("Timeout.")), connection: connection)
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    connection.send(content: query, completion: .contentProcessed { sendError in
                        if let sendError {
                            state.finish(.failure(sendError.localizedDescription), connection: connection)
                            return
                        }
                        connection.receiveMessage { data, _, _, recvError in
                            if let recvError {
                                state.finish(.failure(recvError.localizedDescription), connection: connection)
                                return
                            }
                            guard let data, data.count >= 12 else {
                                state.finish(.failure(AppLocalization.string("No response.")), connection: connection)
                                return
                            }
                            let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                            let ms = max(1, Int(elapsedNanos / 1_000_000))
                            state.finish(.success(ms), connection: connection)
                        }
                    })
                case .failed(let error):
                    state.finish(.failure(error.localizedDescription), connection: connection)
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    static func makeDnsQuery(for domain: String) -> Data {
        var data = Data()
        let id = UInt16.random(in: 1...UInt16.max)
        data.append(UInt8((id >> 8) & 0xff))
        data.append(UInt8(id & 0xff))
        data.append(contentsOf: [0x01, 0x00]) // flags: standard query, RD=1
        data.append(contentsOf: [0x00, 0x01]) // QDCOUNT=1
        data.append(contentsOf: [0x00, 0x00]) // ANCOUNT=0
        data.append(contentsOf: [0x00, 0x00]) // NSCOUNT=0
        data.append(contentsOf: [0x00, 0x00]) // ARCOUNT=0

        for label in domain.split(separator: ".") {
            let bytes = Array(label.utf8)
            let len = min(bytes.count, 63)
            data.append(UInt8(len))
            data.append(contentsOf: bytes.prefix(len))
        }
        data.append(0x00)                     // root terminator
        data.append(contentsOf: [0x00, 0x01]) // QTYPE=A
        data.append(contentsOf: [0x00, 0x01]) // QCLASS=IN
        return data
    }
}

private final class PingContinuationState: @unchecked Sendable {
    private var continuation: CheckedContinuation<ProfilePingResult, Never>?
    private let lock = NSLock()

    init(continuation: CheckedContinuation<ProfilePingResult, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: ProfilePingResult, connection: NWConnection) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        connection.cancel()
        pending.resume(returning: result)
    }
}
