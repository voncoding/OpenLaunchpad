# Interaction regression checks

Run from the repository root on macOS with Xcode or Command Line Tools installed:

```sh
./scripts/test-interactions.sh
```

The script compiles the production Swift sources with the project's main-actor
isolation and concurrency settings, then runs 56 checks for drag intent, folder
boundaries, keyboard navigation, folder closure and selection restoration, page
restoration, catalog refresh races, and persistent page boundaries. The scrollbar check hosts the real folder
offscreen with the system scroll-bar preference set to Always for the test process;
it verifies that indicators stay hidden while keyboard scrolling still works.
The pager check hosts the real grid offscreen and verifies full-viewport clipping,
icon hit targets, and page snapping when a swipe ends or is cancelled outside it.
Wallpaper checks use synthetic wallpaper-service plists and temporary files to
verify Photos asset matching, settings refresh, display precedence, and safe
handling of missing assets, folders, and shuffle configurations. They also verify
lazy access to protected photo preferences, distinguish permission failures from
missing files, and prevent a denied photo selection from becoming a default image.
It does not require an Xcode test target or display the launcher on screen.

Catalog checks inject a scan operation and monotonic clock to verify that repeated
opens share a scan, expired snapshots refresh, and changes during a scan are not
lost. Reopening after a deferred folder refresh applies app installations and removals immediately without an extra scan. Filesystem checks watch real temporary directories for installation, resource
updates, renames, removal, and missing-root recreation. Icon checks exercise shared
loads, memory hits, revision invalidation, bounded concurrency, and a blocked worker
that must not block render-time cache queries.

Tests use fictional application URLs, temporary preference suites, and a temporary
Foundation home for caches. They never launch an installed application. Build
outputs and test data are removed when the script exits.

If Xcode is installed outside `/Applications/Xcode.app`, set `DEVELOPER_DIR` to its
`Contents/Developer` directory. The runner also supports Command Line Tools with the
macOS 26.5 SDK: this avoids depending on SwiftUI macro plugins available only in full
Xcode's newer SDK. `SDKROOT` can explicitly select a different compatible SDK.
Environments that prohibit nested sandboxes must
allow Xcode's Swift macro plugin process to run before these checks can compile.
