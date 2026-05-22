import Foundation

public enum ClientStatus: Equatable {
    case stopped
    case starting
    case ready
    case stopping
    case failed(String)

    public var title: String {
        switch self {
        case .stopped: AppLocalization.string("Disconnected")
        case .starting: AppLocalization.string("Connecting...")
        case .ready: AppLocalization.string("Connected")
        case .stopping: AppLocalization.string("Disconnecting...")
        case .failed: AppLocalization.string("Error")
        }
    }

    public var isRunning: Bool {
        switch self {
        case .starting, .ready, .stopping: true
        case .stopped, .failed: false
        }
    }
}
