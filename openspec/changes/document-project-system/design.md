# Design: Documentation System

## Structure

The documentation set is organized by maintenance question:

- "What is the system?" -> `docs/architecture.md`
- "How do I deploy or update it?" -> `docs/deployment.md`
- "How do I configure it?" -> `docs/configuration.md`
- "Where is the logic?" -> `docs/modules.md`
- "How do I operate it?" -> `docs/operations.md`, `docs/usage-examples.md`
- "How do I debug it?" -> `docs/troubleshooting.md`, `docs/faq.md`
- "How do I keep it safe?" -> `docs/security.md`
- "How do I maintain it?" -> `docs/maintenance.md`

## Decisions

- Keep docs in Markdown under `docs/` so installer copies them with the existing install flow.
- Keep deployment honest: local macOS is supported; container/server are validation-only or unsupported for real switching.
- Avoid duplicating every command from README. Link and specialize each document by role.
- Include OpenSpec project context under `openspec/` without adding a tool dependency.

## Risks

- Docs can drift from scripts as behavior changes.
- Mitigation: maintenance guide explicitly requires docs updates with behavior changes, and README/docs index names ownership areas.

## Validation

- Run `./check.sh`.
- Review links and file names.
- Confirm no credential examples or private local account paths are introduced.
