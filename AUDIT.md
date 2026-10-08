# NetCapture 0.2.2 Source Audit

Audit scope: all source, packaging, protocol, IPC, database and GitHub Actions files currently compiled by this repository.

## Fixed in this audited revision

- Replaced `IMP -> void *` storage with byte-preserving `NSData` storage, avoiding Xcode 26's strict function-pointer conversion diagnostic.
- Serialized hook installation and retained the ancestor-hook recursion guard.
- Added runtime `NSURLSession` factory hooks so custom session implementation classes receive the completion-handler creation hooks.
- Added `dataTaskWithURL:completionHandler:` coverage alongside the request variant.
- Added `NSURLSessionTask -cancel` observation. `cancel_requested` now means the application requested cancellation rather than merely inferring it from the final error.
- Kept application callbacks outside capture `@try/@catch`, so capture exceptions cannot swallow exceptions thrown by application completion handlers.
- Fixed the daemon request-body hole: `REQ_BODY` and `REQ_BODY_END` now persist to dedicated request body files and SQLite columns.
- Split request/response body filenames; body writer no longer hard-codes `response.body` for every direction.
- Closed body states at `HOP_END`/disconnect so late body frames cannot reopen an `O_TRUNC` file.
- Added per-connection transaction and per-transaction hop caps.
- Tightened HELLO validation (`role`, protocol version, no payload), rejects duplicate HELLO, unknown capture message types and invalid payload shapes.
- Added owner UID verification on accepted Unix-domain clients.
- Tightened runtime directory/socket permissions to `0700`/`0600` for the mobile-user daemon model.
- Added SQLite extended result codes, cleanup on failed initialization, explicit column lists, request-body migration for earlier Phase 2.1 databases, `user_version`, indexes and atomic rollback behavior.
- Retained plain `INSERT` semantics; no `INSERT OR REPLACE` parent-row cascade hazard.
- Made IPC queue-budget arithmetic overflow-safe and rejects invalid JSON metadata before enqueueing.
- Restored the GitHub Actions dependency fix: only `ldid` and `xz` are installed. No Homebrew `dpkg`, GNU `make`, `gmake`, or `dpkg-deb` dependency.
- Forced Theos/dm.pl xz package compression via `THEOS_PLATFORM_DEB_COMPRESSION_TYPE = xz` and inspect the `.deb` with macOS `ar`/`tar`.
- Bumped package version to 0.2.2.

## Current compiled coverage

This is intentionally still the completion-handler MVP:

- `NSURLSession dataTaskWithRequest:completionHandler:`
- `NSURLSession dataTaskWithURL:completionHandler:`
- task `resume` / `cancel` lifecycle observation
- request headers and in-memory `HTTPBody`
- response headers/body from the completion block
- transport error classification
- local AF_UNIX protocol v2
- daemon parser/assembler
- request + response body files (32 MiB storage cap per body)
- SQLite WAL persistence

## Explicitly not claimed in 0.2.2

Delegate callbacks, redirects, `NSURLSessionTaskMetrics`, download temporary-file capture, streamed request body proxy/retries, upload-task special paths, NSURLConnection, CFNetwork observations/dedup, viewer API and HAR export are not compiled into this audited baseline yet.

## Remaining runtime risks to validate on device

- iOS sandbox policy may restrict connecting from a target app process to the shared Unix socket path on some jailbreak configurations. This cannot be proven in the build runner and must be device-tested.
- launchd loading behavior varies by jailbreak/package manager. A userspace reboot may be required after first install if the package manager does not bootstrap the daemon plist immediately.
- The project links against Theos' Substrate stub and declares `ellekit` as the runtime dependency; actual device compatibility must be verified with the installed ElleKit version.

## Release gate for this baseline

1. GitHub Actions produces the rootless `.deb` for arm64/arm64e without warnings promoted to errors.
2. Install on an iOS 15+ rootless jailbreak with ElleKit.
3. Confirm `netcaptured` is running and the socket exists.
4. Run a small GET, POST with body, 404, timeout and cancel case in the selected test app.
5. Confirm `capture.sqlite3` contains one transaction per completion request and request/response body files match observed sizes up to the configured cap.
6. Kill `netcaptured` and confirm the target app continues networking normally.

## 0.2.3 Xcode 26 nullability audit

All public Objective-C headers that import Foundation are now wrapped in `NS_ASSUME_NONNULL_BEGIN/END`. APIs that can legitimately be nil are explicitly annotated (`nullable` / `_Nullable`), including completion payloads, error objects, optional error-out parameters, session IDs/body paths, close handlers, and nullable original IMP lookups. Matching implementation signatures were updated where useful to avoid header/implementation drift under Xcode 26 diagnostics.


## 0.2.4 Xcode 15/Objective-C++ compatibility pass

- Replaced GNU-style `typeof(...)` weak/strong declarations in `.mm` files with explicit Objective-C class types.
- Added explicit `(const uint8_t *)` conversions for `NSData.bytes`, because Objective-C++ does not permit implicit `const void *` to byte-pointer conversion.
- Applied the same fixes to Tweak IPC, daemon IPC/server, and body writer rather than patching only the first compiler error.
