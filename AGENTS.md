# Docktap — agent notes

Native AppKit menu-bar app. Click the focused app’s Dock icon to minimize; click again to restore.

## Layout

- `Sources/` — the app. `AppDelegate.swift` + `ClickMonitor.swift` are the core.
- `Resources/Info.plist` — bundle id `com.astucore.docktap`.
- `scripts/build.sh` — compile, sign with a *local* identity, install to `/Applications/Docktap.app`, rewrite and bootstrap KeepAlive (`keep-alive.sh`). Never leave the app off after a build.
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
7. KeepAlive must stay loaded (`launchctl print gui/$(id -u)/com.astucore.docktap`). Process parent should be launchd.
8. Prefer a **Developer ID Application** identity when one exists (`scripts/codesign-app.sh`). Do not mint a new local cert if a Developer ID is available — that resets Accessibility. Do not sign Docktap with Snaplane’s identity.

## Autonomous maintenance

When Grok Bot is asked to maintain this repo:

- **New issue:** label `bug` / `enhancement` / `question`. Reply once with a short confirmation or a clarifying question. Close obvious duplicates and spam.
- **New or updated PR:** compile locally or wait for CI. Review for signing-key leaks, hardcoded `/Users/mac` paths that break other machines, and behavior regressions. Comment; do not merge.
- **CI red:** fix compile errors on a branch and push. Do not rewrite `main` history.
- **README / clone URL drift:** keep `https://github.com/Astucore-ai/docktap` as the canonical remote.
- Notify the owner only for security reports, permission-model changes, or anything that needs a notarized release.

Org: [Astucore-ai](https://github.com/Astucore-ai).

## Scope and simplicity constraint

Do not introduce unnecessary complexity, abstraction, or security hardening at this time.

Stay inside the current request. Implement only what is needed to complete the stated task correctly.

- Do not add extra layers, wrappers, factories, config systems, feature flags, plugin architecture, or “future-proofing” unless the task explicitly requires them.
- Do not add new auth, encryption, rate limiting, input sanitization frameworks, CSP, CSRF, secrets rotation, least-privilege redesign, or other security hardening unless the current task is itself a security fix or the existing code already requires it to function.
- Do not refactor adjacent code “while we are here.”
- Do not introduce new dependencies unless they are required for the requested change.
- Prefer the simplest working change that matches existing patterns in this codebase.
- If a more robust or more secure design would be better later, note it briefly as a follow-up. Do not implement it now.

Default to: smallest correct change, existing conventions, no extra surface area.
