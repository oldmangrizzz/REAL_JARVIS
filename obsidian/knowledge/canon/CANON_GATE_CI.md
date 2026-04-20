# canon-gate — GitHub Actions workflow

**File:** `.github/workflows/canon-gate.yml`.
**Added:** 2026-04-20 (commit `8396d57`).
**Triggers:** `push` to `main`, `pull_request` targeting `main`.

## Two jobs

### 1. `non-dom-invariant` (runs on `ubuntu-latest`)

Greps every Swift source file under:
- `Jarvis/Mac/`
- `Jarvis/Mobile/`
- `Jarvis/Watch/`
- `Jarvis/TV/`
- `Jarvis/Shared/`

...for the banned pattern:

```
WKWebView|UIWebView|loadHTMLString|innerHTML|document\.createElement|WebKitView
```

Any hit fails the job. This is the structural embodiment of the doctrine: **the DOM was retired in the 1990s where it belongs** — no WebView shims ever sneak into JARVIS platform apps.

### 2. `canon-tests` (runs on `macos-14`)

1. Selects the default Xcode.
2. Runs the full test suite:
   ```
   xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS' test
   ```
3. Parses the `Executed N tests, with 0 failures` line from `xcodebuild.log`.
4. Enforces `N >= 138` (the canon floor as of 2026-04-20).

The floor **rises** as new canon SPECs land. It never drops. If you delete tests, you're deleting canon. Touch the floor = dual signature conversation.

## Failure semantics

Both jobs are hard gates. A red canon-gate run blocks:
- Merging into `main`.
- Issuing "Phase Complete" claims per [[canon/VERIFICATION_PROTOCOL]].
- Any downstream release artifact.

## Why two jobs

- **Ubuntu + grep** is fast and catches the cheap regression (someone imports WebKit). Runs in seconds.
- **macOS + xcodebuild** is slow but exercises the real test fabric. Runs in ~15 min cold.

Keeping them separate means the structural check never waits on the behavioral one.

## Related
- [[canon/VERIFICATION_PROTOCOL]] · [[canon/ADVERSARIAL_TESTS]]
- [[reference/BUILD_AND_TEST]]
- [[codebase/testing/TestSuite]]
