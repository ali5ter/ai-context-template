# ai-context-template

A template repository for keeping AI context files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) private while
keeping them version-controlled and available across machines via symbolic links.

Inspired by Dan Maby's article
[Managing AI Configuration Files Across Projects](https://www.danmaby.com/posts/2025/08/managing-ai-configuration-files-across-projects/).

## The problem

AI context files often contain sensitive project details — architecture decisions, team conventions, deployment
specifics — that should not live in public repositories, yet discarding them means losing version control and
the ability to share context across machines or with teammates.

## The solution

Store AI context files in a private repository (created from this template), organized by source repo name.
`install.sh` symlinks each file back into its project directory so local AI tooling finds it as normal.
`extract-ai-context.sh` automates moving a file out of a public repo and into this one.

## Using this template

1. Click **Use this template** on GitHub to create your own private `ai-context` repo
1. Clone it locally:

```bash
cd ~/Documents/Projects   # or ~/src on Linux
gh repo clone <your-username>/ai-context
```

1. Run the installer to create symlinks:

```bash
cd ai-context
./install.sh
```

## Structure

```text
ai-context/
├── extract-ai-context.sh  # Moves AI context files from a public repo into this one
├── install.sh             # Creates symlinks into local project directories
├── README.md
└── <repo-name>/
    └── CLAUDE.md          # (or AGENTS.md or GEMINI.md — multiple files supported)
```

Each subdirectory is named after the source repository.

## extract-ai-context.sh

Automates the full extraction workflow for a public repo: untracks the AI context file(s), adds them to
`.gitignore`, stores them here, and symlinks them back so local AI tooling is unaffected.

```bash
./extract-ai-context.sh <path-to-repo>
```

What it does:

1. Finds all of `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` present in the target repo
1. Runs `git rm --cached` to untrack each file
1. Appends each filename to `.gitignore` in the target repo
1. Copies the files into `<repo-name>/` here and pushes
1. Symlinks the original paths back to the copies here
1. Pushes the updated target repo

## install.sh

Scans each subdirectory and creates symlinks in the matching local project directory.

```bash
./install.sh [--dry-run] [--projects-dir <path>]
```

| Option                  | Default                                           | Description                       |
|-------------------------|---------------------------------------------------|-----------------------------------|
| `--dry-run`             |                                                   | Preview symlinks without creating |
| `--projects-dir <path>` | `~/Documents/Projects` (macOS) or `~/src` (Linux) | Override the projects root        |

## Setup on a new machine

```bash
cd ~/Documents/Projects   # or ~/src on Linux
gh repo clone <your-username>/ai-context
cd ai-context
./install.sh
```
