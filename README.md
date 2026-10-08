# NetCapture Phase 2

Phase-2 engineering baseline for a local, authorized iOS NSURLSession capture/logger using ElleKit-compatible Substrate hooks.

## What is wired

- Theos tweak + launch daemon targets.
- Protocol v2 framing over local AF_UNIX.
- Daemon accept/parser/assembler.
- SQLite WAL persistence.
- Response body files with a 32 MiB per-body storage cap.
- `NSURLSession dataTaskWithRequest:completionHandler:` creation/completion capture.
- `NSURLSessionTask -resume` observation.
- Raw request/response headers and bodies (no redaction).
- Fail-open capture path: capture errors are not allowed to change app callbacks.

## Deliberately deferred

This package is the compile-focused Phase-2 baseline, not the final coverage build. Delegate interception, redirects, metrics, download temp-file capture, streamed request-body proxy, CFNetwork and NSURLConnection are kept out of the compiled target until this baseline is device-validated. The architecture from Phase 1 remains compatible with adding them afterward.

## Build

```sh
export THEOS=/path/to/theos
make clean package FINALPACKAGE=1
```

The Makefile links `libellekit` but includes the standard Substrate API header (`<substrate.h>`), matching ElleKit's Substrate compatibility API.

## Runtime path

Current baseline uses `/var/mobile/Library/NetCapture`. For a production rootless/rootful package, replace `NCRuntimePaths` with package-specific runtime path/ownership policy rather than embedding `/var/jb` paths in business code.

## Injection filter

By default the tweak only loads in `com.example.NetCaptureTest`. Rebuild with your test bundle ID, or launch with the `NC_CAPTURE_BUNDLE` environment value during controlled testing.

## Expected test

A completion-handler request should produce:

`HELLO -> TX_BEGIN -> HOP_BEGIN -> HOP_RESPONSE -> RESP_BODY -> RESP_BODY_END -> HOP_END -> TX_END`

Then inspect `capture.sqlite3` with `Tests/query.sql` and the `Bodies/` directory.

## Known validation boundary

The generated project was source-audited in this environment, but a real iOS/Theos compile cannot be executed here because the container does not contain Apple's iOS SDK, Foundation headers, Theos, or the target ElleKit installation. Run `make` in your jailbreak build environment; the remaining work should be normal SDK/header/package-path adaptation rather than architecture work.

## Phase 2.1 hardening

This revision focuses on build/runtime blockers before expanding hook coverage:

- Rootless package scheme and `/var/jb/usr/libexec/netcaptured` launch path.
- launchd daemon runs as `mobile`, so the `0700` runtime directory and local socket remain reachable by injected app processes without using `0777` permissions.
- `NCHookRegistry` materializes inherited methods before hooking and stores the original IMP per `(Class, SEL)`.
- NSURLSession creation hook is installed on both the public base class and the current `sharedSession` runtime class; task `resume` is also installed on each observed task runtime class.
- HTTP request bodies are chunked to `NC_MAX_PAYLOAD_SIZE` instead of attempting to send an oversized frame.
- IPC client now has a bounded enqueue budget, FIFO partial-send handling, `EAGAIN` write-source continuation, and clears queued frames on connection loss. The target request thread never waits for daemon socket writes.
- SQLite persistence uses `INSERT` inside an explicit transaction rather than `INSERT OR REPLACE`, avoiding accidental parent-row replacement/cascade semantics.

This is still an NSURLSession completion-handler MVP. Delegate callbacks, redirects, TaskMetrics, download-file capture, streamed body proxies, NSURLConnection, CFNetwork observations/dedup and HAR are intentionally not claimed as compiled Phase 2.1 coverage yet; those should be added only after this build runs cleanly on-device.

## GitHub Actions build (no local compiler required)

This package includes `.github/workflows/build.yml`.

1. Create a GitHub repository and upload the **contents of this folder** to the repository root.
2. Open **Actions → Build NetCapture rootless deb → Run workflow**.
3. Enter the target app's bundle ID (for example `com.example.app`).
4. After the workflow finishes, open the workflow run and download the artifact named **NetCapture-rootless-deb**.
5. The artifact contains the installable rootless `.deb` plus `package-contents.txt`.

The workflow uses a macOS runner, Xcode's iOS SDK, Theos, and Theos' Substrate link stub. The package still declares an `ellekit` runtime dependency; ElleKit provides Substrate-compatible APIs on the device.

If a build fails, download/copy the full **Build rootless package** log. It is the authoritative next input for SDK/source fixes.
