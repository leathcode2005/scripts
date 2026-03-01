# Copilot Instructions for `scripts`

## Current repository shape
- This repository is currently a minimal scaffold.
- Only `README.md` and `.git/` exist on `main` (initial commit only).
- There are no application source files, package manifests, CI workflows, or test configuration yet.

## How to work effectively here
- Treat this repo as **scripts-first and convention-light** until explicit structure is added.
- Prefer small, focused additions over large frameworks unless the prompt asks for full scaffolding.
- When adding new code, also add/expand `README.md` with:
  - what the script does,
  - how to run it,
  - required dependencies.

## Architecture guidance (present state)
- No multi-component architecture exists yet.
- No service boundaries, data contracts, or inter-process communication patterns are established.
- If a task introduces architecture (for example multiple scripts/modules), document the chosen layout in `README.md` at the same time.

## Build, test, and run workflows
- There are currently no discoverable build/test commands in-repo.
- Before proposing commands, inspect newly added manifests (for example `package.json`, `pyproject.toml`, `Makefile`, or shell scripts) and use those as the source of truth.
- If adding a runnable script, include an explicit invocation example in `README.md`.

## Project-specific conventions to preserve
- Keep changes minimal and directly tied to the user request.
- Do not assume language/runtime/tooling until files establishing them are present.
- Avoid introducing unrelated lint/format/build systems in the same change unless requested.

## Key files to check first
- `README.md` — primary user-facing documentation; update it whenever a script is added or changed.
- `gentoo-tools.sh` — Gentoo admin menu; entry point is the `main()` loop, individual options are `opt_*` functions.
- `crux-tools.sh` — CRUX Linux admin menu; same structure as gentoo-tools.sh, CRUX-native commands (`prt-get`, `pkgmk`, `ports`).
- `.github/copilot-instructions.md` — agent behavior for this repo; keep it updated as structure appears.

## Script conventions (established by gentoo-tools.sh)
- All output goes through helper functions: `INFO`, `SUCCESS`, `WARN`, `ERROR`, `LABEL`, `HEADER`, `HR` — do not use raw `echo` for user-facing messages.
- Idempotent file edits: use `update_conf()` pattern (grep-and-sed in-place, else append) rather than blindly appending.
- Always take a timestamped backup before modifying system files (`/etc/portage/make.conf`, `/etc/fstab`, etc.).
- Functions that require root call `require_root` at the top and return early on failure.
- Each menu option ends with `press_enter` so the user can read output before the menu redraws.

## When expanding this repository
- Mirror existing patterns once they exist; until then, prefer clear naming and shallow directory depth.
- Add only the minimum configuration required to run/test the requested feature.
- If you create a new top-level area (for example `scripts/`, `src/`, `tests/`), briefly explain its purpose in `README.md`.