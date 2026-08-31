import Foundation
import GRDB
import StorageContracts

/// Owns the database. Nothing else in the project may.
///
/// `internal`, like every implementation type here — the composition root gets
/// a `StorageSet` of protocols and cannot name this.
final class SQLiteStorage: Sendable {
    let pool: DatabasePool

    init(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var configuration = Configuration()
            // Foreign keys are off by default in SQLite. `parent_id` points at
            // `notebook(id)`, and without this the reference is decoration.
            configuration.foreignKeysEnabled = true

            pool = try DatabasePool(path: url.path, configuration: configuration)
            try Migrations.migrator().migrate(pool)
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.unavailable(
                "could not open the database at \(url.lastPathComponent): \(error)"
            )
        }
    }

    /// A read outside any transaction.
    func read<T: Sendable>(
        _ body: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        do {
            return try await pool.read(body)
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.unavailable("read failed: \(error)")
        }
    }

    /// A write in its own transaction, for storage's own bookkeeping.
    ///
    /// Callers reach writes through `TransactionRunning`, never through this.
    func write<T: Sendable>(
        _ body: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        do {
            return try await pool.write(body)
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.unavailable("write failed: \(error)")
        }
    }
}
