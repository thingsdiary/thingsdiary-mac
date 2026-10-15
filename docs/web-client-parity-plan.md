# Web client parity plan

Status: approved on 2026-10-15.

## Goal

Bring the user-facing behavior from `thingsdiary` `master` to the Swift client and macOS app. The first complete path covers registration, public-key display, diary selection, note creation and editing, durable local data, and synchronization. Topic, template, archive, trash, bookmark, duplicate, search, and settings behavior follows as vertical slices.

The web app is an IndexedDB-only application. It has no authentication, diary selector, API client, or remote synchronization to port. Those behaviors must be composed from the `thingsd` API and the existing Swift crypto client.

## Proposed public seams

1. `ThingsDiaryClient` exposes plaintext entries. The encrypted API envelope becomes an implementation detail. Returned entries retain their server version.
2. Registration generates a `TDKV1` secret key and KDF salt, returns the secret key for one-time display, and exposes only the signing and encryption public keys to the UI.
3. SwiftUI invokes user commands on one `@MainActor ThingsDiaryAppModel`. Views do not handle network requests, ciphertext, cursors, or the outbox.
4. One concrete `DiaryStore` actor owns local entries, the pending-write outbox, and synchronization checkpoints. A separate generic repository or sync framework is not introduced for the MVP.

## TDD slices

Each slice starts with one failing test at a confirmed public seam, implements the smallest complete user behavior, and ends with the full relevant suite passing.

1. Register an account, enter the authenticated state, and display the generated secret key and two public keys.
2. Load every diary page, select a diary, and load every plaintext entry page. Ignore stale responses after a rapid diary switch.
3. Create and update an entry online. Verify `create -> read -> update -> read` against the live API without launching the GUI.
4. Persist the selected diary and its entries. Reopen the store without a network connection and recover the last downloaded state.
5. Save an entry and its outbox record atomically. Retry a stable client-generated entry ID after a lost response without creating a duplicate.
6. Pull the changes feed, apply create/update/delete events, persist the checkpoint atomically, and deduplicate repeated events.
7. Preserve both local and server content on a version conflict. Do not silently overwrite either copy.
8. Add topics and templates, followed by bookmark, archive, trash, restore, duplicate, search, sorting, and local settings.

## Protocol constraints

- Entry PUT is an upsert keyed by a client-generated UUID. Reusing the ID makes a retried create address the same server entity.
- Versions are Unix timestamps in milliseconds. The server rejects a version only when the stored version is greater, so this is timestamp-based last-write-wins rather than a true expected-revision compare-and-swap.
- The changes page token is a sequence cursor, but the final page does not return a durable next token. A client checkpoint therefore needs the last server timestamp plus change-ID deduplication until the server exposes a final cursor.
- Search, sorting, bookmark, archive, and settings are local behavior. The zero-knowledge API cannot search decrypted note contents.
- SwiftData is available at the current macOS 15.8 deployment target. Persistent note data belongs to the app; credentials, the secret key, private keys, and the token remain in memory.

## Deferred infrastructure

Do not add a generic repository layer, use-case objects, an event bus, a standalone sync engine, automatic conflict merging, realtime transport, or a background scheduler until a concrete user behavior requires one. Initial synchronization runs on diary open, after a local save, and on explicit retry.
