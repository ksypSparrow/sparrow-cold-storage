import Foundation
internal import GRDB
import SparrowDomain
import StorageContracts

/// Runs a write as one SQLite transaction, then announces what it touched.
struct SQLiteTransactionRunner: TransactionRunning {
    let storage: SQLiteStorage
    let broadcaster: ChangeBroadcaster

    func write<T: Sendable>(
        _ body: @Sendable (any StorageSession) throws -> T
    ) async throws -> T {
        let touched = TouchedIdentifiers()

        let result: T
        do {
            result = try await storage.pool.write { db in
                let validity = SessionValidity()
                defer { validity.invalidate() }
                return try body(
                    SQLiteSession(
                        db: db, validity: validity,
                        touched: touched, now: Date()
                    )
                )
            }
        } catch let error as StorageError {
            throw error
        } catch let error as DatabaseError {
            throw StorageError.constraintViolated(error.message ?? "\(error)")
        }

        // ⚠️ **After** the write closure returns, which is after COMMIT.
        //
        // GRDB offers `TransactionObserver`, whose `databaseDidCommit` fires
        // while still inside the write barrier. Publishing from there would let
        // a consumer read the database from inside the writer's own critical
        // section — and anything it read could still be rolled back if the
        // enclosing operation failed. Here there is nothing left to roll back.
        if !touched.notes.isEmpty {
            broadcaster.publish(.notes(Array(touched.notes)))
        }
        if !touched.notebooks.isEmpty {
            broadcaster.publish(.notebooks(Array(touched.notebooks)))
        }
        if !touched.tags.isEmpty {
            broadcaster.publish(.tags(Array(touched.tags)))
        }
        return result
    }
}
