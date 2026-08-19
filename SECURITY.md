# Security

Docktap is a local macOS menu-bar app. It asks for **Accessibility** (and sometimes **Input Monitoring**) so it can see Dock clicks and minimize windows.

Do not commit anything under `signing/`, `*.p12`, `*.cer`, or `*.keychain-db`. Those are machine-local code-signing identities.

To report a vulnerability, open a [private security advisory](https://github.com/Astucore-ai/docktap/security/advisories/new) or email the org owner via GitHub. Do not file a public issue for a live exploit.
