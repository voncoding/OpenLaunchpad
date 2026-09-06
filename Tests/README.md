# Interaction regression checks

Run from the repository root on macOS with full Xcode installed:

```sh
./scripts/test-interactions.sh
```

The script compiles the production Swift sources with the project's main-actor
isolation and concurrency settings, then runs 31 checks for drag intent, folder
boundaries, keyboard navigation, folder closure and selection restoration, page
restoration, catalog refresh races, and persistent page boundaries. The scrollbar check hosts the real folder
offscreen with the system scroll-bar preference set to Always for the test process;
it verifies that indicators stay hidden while keyboard scrolling still works.
The pager check hosts the real grid offscreen and verifies full-viewport clipping,
icon hit targets, and page snapping when a swipe ends or is cancelled outside it.
It does not require an Xcode test target or display the launcher on screen.

Tests use fictional application URLs, temporary preference suites, and a temporary
Foundation home for caches. They never launch an installed application. Build
outputs and test data are removed when the script exits.

If Xcode is installed outside `/Applications/Xcode.app`, set `DEVELOPER_DIR` to its
`Contents/Developer` directory. Environments that prohibit nested sandboxes must
allow Xcode's Swift macro plugin process to run before these checks can compile.
