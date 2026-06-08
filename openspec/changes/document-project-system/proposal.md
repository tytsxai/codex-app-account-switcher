# Proposal: Document Project System

## Problem

The project already had quick-start, operations, security, usage examples, and FAQ documents, but lacked a complete documentation system for architecture, deployment modes, configuration, key modules, troubleshooting, and maintainer handoff. A new maintainer could run the happy path but would still need to reverse-engineer core scripts before safely changing or operating the project.

## Goals

- Document the actual local-first architecture and runtime data model.
- Document supported local deployment and explicitly define container/server limitations.
- Centralize environment-variable configuration.
- Map key modules to responsibilities, write targets, and core logic.
- Provide a practical troubleshooting guide for common statuses and failure modes.
- Add a maintainer guide and local OpenSpec baseline.
- Update documentation indexes so the system is discoverable.

## Non-Goals

- Change runtime behavior.
- Add a server, container runtime, or hosted deployment model.
- Document or expose real account credentials.
- Replace existing README, operations, FAQ, or usage examples.

## Acceptance Criteria

- `docs/README.md` links to the full documentation set.
- `README.md` documentation section points maintainers to architecture, deployment, configuration, modules, operations, troubleshooting, security, usage examples, and FAQ.
- New docs reflect the current Bash and Node.js implementation.
- OpenSpec change record exists for this documentation-system work.
- `./check.sh` passes after documentation changes.
