# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`ai-context-template` is a GitHub template repository for keeping AI context files (`CLAUDE.md`, `AGENTS.md`,
`GEMINI.md`) private while keeping them version-controlled and available across machines via symbolic links.

Inspired by Dan Maby's article
[Managing AI Configuration Files Across Projects](https://www.danmaby.com/posts/2025/08/managing-ai-configuration-files-across-projects/).

**The problem it solves:** AI context files often contain sensitive project details that should not live in
public repositories, yet teams still need version control and cross-machine availability.

**The solution:** A private repo (created from this template) stores the files, organized by source repo name.
Symbolic links connect each file back into its project directory so local AI tooling finds it transparently.

## Design Decisions

### Why the scripts live here, not in the source repos

`extract-ai-context.sh` and `install.sh` both live in the ai-context repo itself (not in carrybag-lite or any
other project), so they ship automatically with every instance created from this template. The tool is
inseparable from the repo it manages.

### No hardcoded usernames or repo paths in public-facing scripts

Earlier iterations defaulted to `ali5ter/ai-context` in `extract-ai-context.sh`. This was removed because the
template is generic — any user's instance should work without editing the script. `SCRIPT_DIR` serves as the
private repo root, making the env var unnecessary.

### Multiple AI context files per repo are supported

The initial design used "first match wins" (stopped at the first file found). This was changed because a repo
may legitimately contain both `CLAUDE.md` and `AGENTS.md` simultaneously. All matching files are now collected
before any git operations run, and processed together in a single commit per repo.

### Single commit per repo per operation

`extract-ai-context.sh` makes one commit to the target repo (all `.gitignore` changes together) and one commit
to this repo (all new files together), regardless of how many AI context files are being moved. This keeps
history clean.

### `install.sh` is purely additive — no deletions

The installer only creates or updates symlinks. It never removes files or symlinks, even if a subdirectory was
deleted from this repo. This is intentional: accidental deletion here should not silently remove files from
project directories.

### Backup before overwriting

Both scripts back up any regular file that would be overwritten by a symlink, using a timestamped suffix
(`.backup.YYYYMMDDHHMMSS`). This protects against data loss when running `install.sh` on a machine that has an
unextracted copy of an AI context file.

### Platform detection for projects root

`install.sh` defaults to `~/Documents/Projects` on macOS and `~/src` on Linux, matching the convention used in
[carrybag-lite](https://github.com/ali5ter/carrybag-lite). Override with `--projects-dir`.

## Repository Structure

```text
ai-context-template/
├── extract-ai-context.sh  # Moves AI context files from a public repo into an instance
├── install.sh             # Creates symlinks from instance into local project directories
├── CLAUDE.md              # This file
└── README.md              # User-facing documentation
```

When a user creates an instance from this template, they add subdirectories:

```text
ai-context/  (personal private instance)
├── extract-ai-context.sh
├── install.sh
├── CLAUDE.md
├── README.md
└── <repo-name>/
    ├── CLAUDE.md          # (and/or)
    └── AGENTS.md          # (and/or)
    └── GEMINI.md
```

## Script Behaviour Reference

### extract-ai-context.sh

Two modes, auto-detected from the argument:

**Single mode** (argument is a git repo): original verbose behaviour unchanged.

1. Resolves the target repo path to absolute
2. Scans for all of `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` — collects regular files only, skips symlinks
3. For each found file: `git rm --cached`, appends to `.gitignore`
4. Makes one commit to the target repo covering all `.gitignore` changes
5. Copies each file into `$SCRIPT_DIR/<repo-name>/`, makes one commit, pushes this repo
6. Creates symlinks: `<target-repo>/<file>` → `$SCRIPT_DIR/<repo-name>/<file>`
7. Pushes the target repo

**Batch mode** (argument is a directory, or no argument — defaults to `~/Documents/Projects` on macOS):

1. Scans every subdirectory for git repos with unextracted AI context files
2. Phase 1 (optionally parallel with `--parallel`): untrack files from each target repo + copy here
3. Phase 2 (sequential): one commit per extracted repo to this repo, then one push
4. Phase 3 (sequential): create all symlinks
5. Phase 4: push each target repo, display per-repo results and summary

**Options:** `--parallel` (batch mode only), `-q/--quiet` (suppress skipped repos)

**Exit codes:** 0 success, 1 bad args/not-a-repo (single mode), 2 no AI context files found (single mode)

### install.sh

1. Scans every subdirectory of `$SCRIPT_DIR` (each is a repo name)
2. For each: checks whether `<projects-root>/<repo-name>` exists locally
3. For each AI file found in the subdirectory: creates symlink into the project directory
4. Backs up any regular file that would be displaced by a symlink
5. Reports linked count and skipped count at completion

**Options:** `--dry-run` (preview only), `--projects-dir <path>` (override projects root)

## Current Status

Initial version created 2026-04-27 as part of
[carrybag-lite](https://github.com/ali5ter/carrybag-lite) development.

### Possible Future Work

- `extract-ai-context.sh`: support extracting from a GitHub repo URL directly (clone, extract, clean up)
- `install.sh`: optional `--repo <name>` flag to re-link a single repo rather than all
- Consider a `remove` or `restore` workflow: move a file back out of this repo into its source repo and
  remove from `.gitignore`
