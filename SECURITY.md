# Security policy

## Supported versions

The latest released version receives fixes. Security issues in older versions
should be resolved by upgrading.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** flow (Security →
Advisories → Report a vulnerability) instead of opening a public issue. Include
the version, a reproduction, and the impact you believe the issue has. You can
expect an acknowledgement within a few days.

## Scope

Finals Rank is a local desktop plugin. It does not run a server, accept inbound
connections, or collect telemetry. The relevant surface is:

- **Settings handling** — the player name, board, platform and season dates are
  user-controlled. The player name is URL-encoded; board and platform are
  validated before they reach a request path.
- **Outbound requests** — made with `curl` using an argument array (no shell).
- **Local history** — stored as JSONL in the user's state directory and never
  uploaded. Writes are serialized with `JSON.stringify`.

No credentials, private keys or API keys are used by this project.
