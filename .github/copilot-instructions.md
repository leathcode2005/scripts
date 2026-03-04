# Copilot Instructions for `scripts`

## Current repository shape
- Two fully-featured interactive Bash admin-menu scripts exist:
  - `gentoo-tools.sh` — Gentoo Linux administration (make.conf, fstab, world rebuild, bootloader, kernel info)
  - `crux-tools.sh` — CRUX Linux administration (pkgmk.conf, fstab, system upgrade, bootloader, kernel info)
- `README.md` documents both scripts with usage, menu-option tables, and dependency lists.
- No CI workflows, package manifests, or automated test infrastructure exist yet.

## How to work effectively here
- Treat this repo as **scripts-first and convention-light**.
- Both scripts follow the same structure: color/helper definitions → `opt_*` functions → `print_menu` → `main` loop.
- When adding a new script or menu option, also update `README.md` with:
  - what the script/option does,
  - how to run it,
  - required dependencies.

## Architecture guidance (present state)
- Flat repo layout: all scripts live at the top level.
- No service boundaries or inter-process communication patterns.
- If a new grouping is introduced (e.g. a `scripts/` subdirectory), document it in `README.md`.

## Build, test, and run workflows
- No automated build or test commands exist yet.
- Manual testing: run `sudo bash gentoo-tools.sh` or `sudo bash crux-tools.sh` on the target system.
- `bash -n <script>` can be used for a quick syntax check without executing the script.
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