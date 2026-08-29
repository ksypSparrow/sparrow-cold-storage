import Foundation

public enum StorageError: Error, Hashable, Sendable {
    case notFound
    case constraintViolated(String)
    case corrupted(String)
    case unavailable(String)
    case migrationFailed(from: Int, to: Int)
}
