# FAQ / 常见问题

## Is this an official OpenAI or Codex product?

No. Codex.app Account Switcher is an unofficial local helper. It depends on user-owned local auth snapshots and current Codex.app behavior.

## Does this project provide accounts or tokens?

No. The repository intentionally contains no real credentials. You must use your own local auth snapshots and keep them outside the repo.

## Does it bypass usage limits?

No. It reads live usage and chooses from accounts you already control. It does not remove limits, fake quota, or make exhausted accounts usable.

## Why does the switcher require live usage validation?

Cached registry data can be stale. The switcher treats API-readable usage as the source of truth before selecting or writing an account, which reduces failed switches caused by expired tokens or exhausted quota.

## Why does it restart Codex.app?

Codex.app reads the active auth state from local files. Restarting the app is the reliable way for the desktop app to pick up the newly written `~/.codex/auth.json`.

## Can I run it from inside Codex.app?

Dry runs are safe. For `--relaunch`, the relaunch script detects when it is running inside Codex.app and refuses to close the current host process. Run the desktop launcher or a normal terminal for real relaunches.

## What happens to rejected source files?

Rejected source files can be copied into `~/.codex/accounts-invalid-sources` for traceability. They are not committed to this repo and should not be retried indefinitely unless you obtain fresh credentials.

## What files are modified during a real switch?

The core write target is `~/.codex/auth.json`. Account import and cleanup commands may also update `~/.codex/accounts/registry.json` and `~/.codex/accounts/*.auth.json`.

## Can this run on Linux or Windows?

The account parsing scripts are mostly portable, but the supported workflow targets macOS because Codex.app relaunch uses `/Applications/Codex.app`, bundle IDs, `open`, and optional AppleScript.

## What should I do before publishing changes?

Run:

```bash
./check.sh
git status --short
```

Also manually inspect examples, screenshots, logs, and docs for real emails, access tokens, refresh tokens, local private paths, and account JSON dumps.
