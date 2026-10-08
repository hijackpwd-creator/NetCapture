# NetCapture 0.2.2 — audited Phase 2 baseline

Local, authorized iOS NSURLSession capture/logger using ElleKit's Substrate-compatible runtime API. This revision is deliberately scoped to a stable completion-handler MVP before expanding hook coverage.

## Compiled coverage

- Theos rootless tweak + `netcaptured` launch daemon.
- Protocol v2 over local AF_UNIX with bounded client queue and partial-send handling.
- Strict HELLO/message parsing and per-client resource caps.
- `NSURLSession dataTaskWithRequest:completionHandler:` and `dataTaskWithURL:completionHandler:`.
- Runtime session-class installation via `sessionWithConfiguration:` factories.
- `NSURLSessionTask -resume` and `-cancel` observation.
- Raw request/response headers and bodies; **no redaction**.
- Request and response body files with a 32 MiB storage cap per direction.
- SQLite WAL persistence with request/response body metadata.
- Fail-open capture behavior: capture exceptions do not alter application callbacks.

See `AUDIT.md` for the complete audit and remaining device-only risks.

## Not claimed yet

Delegate interception, redirects, TaskMetrics, download temp-file capture, streamed body proxy/retries, upload-task-specific paths, NSURLConnection, CFNetwork/dedup, viewer and HAR export remain deferred until this baseline is device-validated.

## GitHub Actions build

The repository contains `.github/workflows/build.yml`.

1. Upload the repository contents to GitHub.
2. Open **Actions → Build NetCapture rootless deb → Run workflow**.
3. Enter the target test application's Bundle ID.
4. Download the `NetCapture-rootless-deb` artifact after the run succeeds.

The workflow uses the macOS Xcode iOS SDK, clones Theos, installs only `ldid` + `xz`, builds the rootless package and inspects the resulting `.deb` using macOS `ar`/`tar`.

## Device data path

```text
/var/mobile/Library/NetCapture/
├── capture.sqlite3
├── capture.sqlite3-wal
├── capture.sqlite3-shm
├── Bodies/
└── Runtime/ncap.sock
```

The daemon runs as `mobile`; runtime directories are `0700` and the socket is `0600`.

## Expected completion-handler flow

```text
HELLO
TX_BEGIN
HOP_BEGIN
[REQ_BODY ...]
[REQ_BODY_END]
HOP_RESPONSE
[RESP_BODY ...]
RESP_BODY_END
HOP_END
TX_END
```

Use `Tests/query.sql` to inspect the database.

## Runtime dependency

The tweak compiles against Theos' Substrate link stub (`libsubstrate.tbd`) and the package declares `Depends: ellekit`. On-device ElleKit supplies the Substrate-compatible API used by `MSHookMessageEx`.

## Important validation boundary

GitHub Actions is the authoritative compiler for this package. Source auditing can catch many correctness issues, but Unix-socket sandbox access, launchd bootstrap behavior, and actual ElleKit/runtime-class behavior require testing on the target jailbroken device.
