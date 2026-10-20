# ADR 0001: SQLite storage and offline synchronization

Status: accepted

Date: 2026-10-21

## Problem

The macOS app currently keeps its durable state in one JSON file. `DiaryStore`
loads the whole file into memory and rewrites the whole value after every
mutation. The same actor also owns network synchronization.

This design has several concrete limits:

- the file has no explicit schema version or ordered migrations;
- every write rewrites unrelated data;
- storage transactions and network orchestration share one type;
- the app waits for the network before showing a selected diary and only falls
  back to cached data after a request fails;
- authentication lives only in process memory, so a restart returns the user to
  the login screen;
- storage errors are discarded by `try?`, which can silently disable durable
  storage;
- a future schema change has no tested upgrade path.

The application must remain useful without a network connection. Local reads
and writes are the primary path. Synchronization is a retryable side effect.

## Motivation

The storage design must provide the following behavior:

1. Notes, diaries, topics, templates, pending writes, conflicts, and sync
   checkpoints survive process restarts.
2. A local mutation and its pending sync operation are committed atomically.
3. A failed or unavailable network never prevents local reads and writes.
4. The last authenticated user can reopen the app without entering credentials
   again while the saved server session remains valid.
5. Every SQLite schema and data-format change is an ordered, tested migration.
6. Production and tests exercise the same database implementation.
7. Existing race guarantees remain intact, including stable create IDs and
   protection of newer edits from stale sync responses.

The first implementation should not introduce infrastructure for portable
vaults, direct CLI database access, multiple processes, background scheduling,
or alternative storage engines.

## Decision

### Local database

Use SQLite through GRDB. Each account database is a private file under the
sandboxed Application Support directory. Its filename is derived from a stable
hash of the normalized login so the login is not exposed in the filesystem.

`DiaryStore` remains a concrete actor and is the only owner of local database
queries and transactions. GRDB types do not escape its boundary. Ordinary
mutations use row-scoped upserts and deletes; only an explicit server snapshot
replacement or one-time legacy import replaces a full domain snapshot.

The initial schema contains:

- `diaries`;
- `entries`;
- `topics`;
- `templates`;
- `sync`.

The `sync` table stores pending local operations and unresolved local conflict
payloads. It does not store completed history, retry telemetry, or generic
background jobs. A network response completes an operation only when the stored
pending write is still the one that produced the request, so a newer local edit
stays queued.

The current synchronization algorithm uses one checkpoint per diary. The first
SQLite version stores `last_sync_at` on `diaries`. Pull synchronization records
the greatest server-issued change timestamp and advances the checkpoint only
after the final page is applied. The boundary is inclusive, so replaying it is
expected and remote application must be idempotent. This avoids relying on the
client wall clock. Persisted page tokens and same-timestamp change-ID arrays are
deferred until evidence shows that replay is too costly or the server exposes a
durable cursor.

### Migrations and versions

`DatabaseMigrator` is the only way to create or change SQLite schema and stored
data formats.

The following rules are mandatory:

- no DDL outside registered migrations;
- released migrations are immutable;
- each new schema or stored-data change gets a new, ordered migration;
- migrations are transactional;
- file-backed and in-memory databases run the same migrator;
- failure to open or migrate the database is visible and prevents storage from
  starting;
- a database created by a newer unsupported application version is rejected;
- migration tests run `foreign_key_check` and `integrity_check`;
- no second hand-written schema-version table is added alongside GRDB's
  migration ledger.

The existing `state.json` is imported only after the SQLite schema is ready. The
import is idempotent and runs in one database transaction. The source JSON is
kept as a recoverable backup after a successful import and remains untouched
after a failed import. Creating that backup is also the durable one-time claim
that prevents the same legacy data from being imported into another account.

### Network synchronization

Move network orchestration to a concrete `DiarySynchronizer` actor.

`DiaryStore`:

- reads and writes local entities;
- saves an entity and its sync operation in one transaction;
- exposes the next pending operation;
- conditionally completes only the current pending operation;
- applies each resolved remote entity atomically;
- advances the pull checkpoint only after the final page succeeds;
- stores the local side of a conflict in `sync` while the server entity remains
  in its domain table.

`DiarySynchronizer`:

- owns calls to `DiaryStoreRemote`;
- coalesces concurrent synchronization requests;
- drains pending local operations;
- pulls paginated remote changes;
- converts remote outcomes into atomic `DiaryStore` commands;
- never keeps a database transaction open across a network `await`.

The app saves locally before requesting synchronization. A network failure
leaves the pending operation on disk and does not roll back the local edit.

No mediator layer is added. `ThingsDiaryAppModel` invokes the concrete store for
local behavior and requests best-effort work from the concrete synchronizer.

### Authentication persistence

Persist the active login, bearer token, and derived signing/encryption
credentials in macOS Keychain. Do not save the password or TDKV1 secret key.
SQLite does not contain bearer tokens or private cryptographic keys.

Add one narrow system-boundary protocol:

```swift
protocol AuthSessionStore: Sendable {
    func load() throws -> SavedAuthSession?
    func save(_ session: SavedAuthSession) throws
    func clear() throws
}
```

Production uses `KeychainAuthSessionStore`. Unit tests use an in-memory test
double because Keychain is an operating-system boundary.

`ThingsDiaryClient` needs a minimal public initializer or method that restores a
previously returned `ThingsDiaryAuthState`. This change belongs in a separate
branch of the sibling `client-swift` repository and has its own tests and atomic
commit.

On startup:

1. Load the saved Keychain session.
2. Open and migrate that login's local database.
3. Show cached data before making network requests.
4. Restore the client authentication state.
5. Check the remote session and synchronize when the network is available.

An unreachable server preserves both the Keychain session and cached data. An
explicit unauthorized response invalidates the saved session but must not erase
the local database. A different successful login opens a different account
database.

### Test seams

TDD tests behavior at these boundaries:

1. `DiaryStore` is the public seam for database migration, reopen, local reads,
   local mutations, pending operations, conflicts, and atomic remote apply.
2. `DiarySynchronizer.synchronize()` is the public seam for push, pull, retry,
   pagination, conflict, and race behavior. It uses a real in-memory
   `DiaryStore` and a fake `DiaryStoreRemote`.
3. `AuthSessionStore` is the public seam for saving, loading, and clearing the
   active session. Keychain itself is covered by a small adapter integration
   test where the test environment permits it.
4. `ThingsDiaryAppModel` is the public seam for cache-first startup, restored
   authentication, offline display, and local-first editing.
5. `ThingsDiaryClient` is the public seam for restoring an auth state and using
   it on authenticated requests.

Tests do not query SQLite tables directly to verify `DiaryStore` behavior. A
small migration-contract suite may inspect schema metadata because schema and
version compatibility are the behavior under test.

## Implementation stages

Each implementation stage follows one vertical red, green cycle at an agreed
seam. After the focused test passes, run the relevant suite, format, lint, build,
and make one atomic commit.

### A. Establish the migration base

1. Add GRDB as a pinned Swift Package dependency.
2. Add `DiaryDatabase` factories for file-backed and in-memory queues.
3. Add the first named migration and migration compatibility checks.
4. Prove through the `DiaryStore` seam that a value written before close is
   available after reopen.
5. Add the migration-contract tests for repeat migration, integrity, foreign
   keys, and unsupported future versions.

Commit: `feat: add versioned SQLite database`

### B. Move the domain snapshot to SQLite

1. Move selected diary persistence behind the existing `DiaryStore` API.
2. Move entries.
3. Move topics.
4. Move templates.
5. Preserve composite diary/entity identity and current delete semantics.

Commit: `feat: persist diary data in SQLite`

### C. Add the durable local mutation path

1. Add the `sync` table migration within the initial unreleased migration. Once
   the migration ships, further changes use a new migration.
2. Save an entry and its pending operation in one transaction.
3. Coalesce later operations for the same entity without losing the queued
   payload.
4. Preserve stable client-generated IDs through restart.
5. Complete a request only while its pending write is still current.

Commit: `feat: queue offline entry changes`

### D. Import the legacy JSON store

1. Detect a legacy `state.json` only when the account database is empty.
2. Import domain rows, pending writes, conflicts, selection, and checkpoint in
   one transaction.
3. Make retry idempotent.
4. Preserve the source file as a backup after success.
5. Surface malformed input without destroying either source.

Commit: `feat: migrate legacy diary storage`

### E. Separate synchronization from storage

1. Introduce the concrete `DiarySynchronizer` actor.
2. Move active-task coalescing from `DiaryStore`.
3. Move push calls one operation at a time.
4. Move pull pagination and remote fetches.
5. Keep all database outcomes as short atomic `DiaryStore` commands.
6. Move existing race tests to the synchronizer seam without weakening their
   assertions.

Commit: `refactor: separate diary synchronization`

### F. Persist and restore authentication

1. In `client-swift`, add and test the minimal auth restoration API.
2. In the macOS app, add `SavedAuthSession` and `AuthSessionStore`.
3. Implement the Keychain adapter with device-local accessibility.
4. Save the login and returned auth state after successful login.
5. Restore the state after restart.
6. Clear the Keychain item on a confirmed unauthorized session.

Commits:

- `client-swift`: `feat: restore saved authentication`
- `thingsdiary-mac`: `feat: persist authenticated session`

### G. Make the application cache-first

1. Make a successfully opened `DiaryStore` mandatory for normal app operation.
2. Add an explicit startup failure state for database errors.
3. Show the saved selected diary and entities before remote calls.
4. Start best-effort synchronization after cached state is visible.
5. Save edits locally before requesting synchronization.
6. Keep cached data visible after network and session-check failures.
7. Refresh the UI from the store after successful synchronization.

Commit: `feat: start from local diary data`

### H. Remove the JSON implementation

1. Remove whole-state JSON persistence and obsolete Codable wrappers.
2. Make the account SQLite store mandatory in production while retaining
   explicit in-memory injection for tests.
3. Keep only the isolated legacy importer and payload codecs until its supported
   migration window expires.
4. Update storage and app-state documentation.

Commit: `refactor: remove legacy storage paths`

### I. Final verification and simplification review

1. Run all unit tests.
2. Run UI tests relevant to login and workspace startup.
3. Run `make format` and `make lint`.
4. Run the macOS build.
5. Run the `client-swift` package tests and build.
6. Review the entire branch diff with an independent quorum for unnecessary
   abstractions, dead code, naming, migration safety, test readability, and
   opportunities to delete code.
7. Apply accepted simplifications in separate atomic commits and rerun every
   verification step.

## Deferred work

- portable vaults and user-selected database paths;
- App Groups and direct CLI database access;
- XPC, local HTTP APIs, file watchers, and distributed notifications;
- `DatabasePool`, WAL tuning, and multi-process coordination;
- periodic background synchronization;
- generic repositories and alternative storage backends;
- automatic conflict resolution;
- persisted retry schedules and sync telemetry;
- encrypted SQLite or SQLCipher;
- multiple simultaneously active accounts;
- full-text search and attachment storage.

## Consequences

The app gains a versioned transactional store, a cache-first startup path, and a
restartable authenticated session. Tests use the same SQLite implementation as
production. Network failures no longer determine whether users can read or edit
local data.

The change adds GRDB, Keychain code, an explicit sync actor, and a small API in
`client-swift`. The database remains plaintext, matching the current JSON
behavior. CLI integration remains a later architectural decision because the
database is private to the sandboxed app.
