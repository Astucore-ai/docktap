# Docktap — agent notes

Native AppKit menu-bar app. Click the focused app’s Dock icon to minimize; click again to restore.

## Layout

- `Sources/` — the app. `AppDelegate.swift` + `ClickMonitor.swift` are the core.
- `Resources/Info.plist` — bundle id `com.astucore.docktap`.
- `scripts/build.sh` — compile, sign with a *local* identity, install to `/Applications/Docktap.app`.
- `scripts/compile-check.sh` — compile only. This is what CI runs.
- `scripts/ensure-identity.sh` — creates a gitignored identity in `signing/`.
- `signing/` — **never commit**. `.gitignore` already covers it.

## Rules

1. Do not commit `signing/`, `*.p12`, `*.cer`, `*.keychain-db`, or logs.
2. Do not merge PRs. Leave them for a human.
3. Do not force-push `main` unless the tree on GitHub is missing the app (the 2026-08-19 incident). Prefer `--force-with-lease` and only then.
4. Public clone + `./scripts/build.sh` must work on Apple silicon macOS 13+. If you add a source file, CI’s compile-check must still pass.
5. Accessibility is bound to the code signature. Rebuilding with a new identity breaks permissions until the user toggles them off/on.
6. Default action is real **minimize**, not Hide.

## Autonomous maintenance

When Grok Bot is asked to maintain this repo:

- **New issue:** label `bug` / `enhancement` / `question`. Reply once with a short confirmation or a clarifying question. Close obvious duplicates and spam.
- **New or updated PR:** compile locally or wait for CI. Review for signing-key leaks, hardcoded `/Users/mac` paths that break other machines, and behavior regressions. Comment; do not merge.
- **CI red:** fix compile errors on a branch and push. Do not rewrite `main` history.
- **README / clone URL drift:** keep `https://github.com/Astucore-ai/docktap` as the canonical remote.
- Notify the owner only for security reports, permission-model changes, or anything that needs a notarized release.

Owner: `@bcovington`. Org: [Astucore-ai](https://github.com/Astucore-ai).
