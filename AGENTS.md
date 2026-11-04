# Repository rules

## Architecture

- Follow `docs/SPEC.md`; distinguish current implementation from planned behavior.
- Keep the existing host desktop running during development. Build/evaluate does
  not imply authorization to activate a host configuration or replace its services.
- Quickshell native services first; Rust only for demonstrated protocol gaps.
- Keep QML assets and Rust in independent build derivations.
- Keep portable build/install commands outside Nix. Put Nix-specific dependency
  wrapping, modules and tests in `nix/` (with the root flake as entry point).
  Arch packaging must be able to use Make/Cargo without evaluating Nix.
- No personal usernames, home paths, credentials or machine-specific display IDs
  in package defaults. User policy belongs in external configuration.
- Never restart a live locker or an active authentication agent for testing.

## What belongs in Git

Commit source, packaging, schemas, portable defaults, documentation, reproducible
tests and small intentional fixtures. Commit `flake.lock` and, once a Rust binary
exists, `Cargo.lock`. Record imported code provenance and preserve license notices.

Do not commit build outputs, Nix result symlinks, Cargo target directories,
runtime state, user configuration, credentials, logs, screenshots, VM disks,
coverage output or temporary investigation scripts. Use `/tmp` for one-off
diagnostics and derivation outputs for test artifacts. Test fixtures must use
synthetic data, have a test consumer and include provenance where applicable.

Do not use broad ignores for JSON, images or lockfiles: legitimate configuration,
assets and test fixtures use those formats too. An ignored file is not a security
boundary; inspect staged contents and new file names before each commit.

## Validation and commits

- Limit local builds to two cores and one Nix build job unless justified.
- Run lightweight checks first; VM tests separately for integration changes.
- Never treat preview compilation as proof of lock, PAM, greetd or suspend safety.
- Each commit should cover a reviewable change; no empty helper frameworks merely
  to claim a backend exists. Do not add runtime Python/Go dependencies for new
  capabilities without revisiting the Rust backend decision.
- Before committing: review `git status --short`, staged diff and
  `git diff --cached --check`; verify no secrets, personal data or generated files.
- Do not push or create releases without user instruction.
