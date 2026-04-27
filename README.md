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
A bootstrap script symlinks each file back into its project directory so local AI tooling finds it as normal.

## Using this template

1. Click **Use this template** on GitHub to create your own private `ai-context` repo
1. Clone it locally:

```bash
cd ~/Documents/projects   # or ~/src on Linux
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
├── install.sh          # Creates symlinks into local project directories
├── README.md
└── <repo-name>/
    └── CLAUDE.md       # (or AGENTS.md or GEMINI.md)
```

Each subdirectory is named after the source repository. The `install.sh` script scans them and creates a
symlink at `<projects-root>/<repo-name>/<filename>` for each one found.

## install.sh options

```bash
./install.sh [--dry-run] [--projects-dir <path>]
```

| Option                  | Default                                           | Description                        |
|-------------------------|---------------------------------------------------|------------------------------------|
| `--dry-run`             |                                                   | Preview symlinks without creating  |
| `--projects-dir <path>` | `~/Documents/projects` (macOS) or `~/src` (Linux) | Override the projects root         |

## Setup on a new machine

```bash
cd ~/Documents/projects   # or ~/src on Linux
gh repo clone <your-username>/ai-context
cd ai-context
./install.sh
```

## Adding repos to your instance

Manually: copy the AI context file into a subdirectory named after the repo, commit, and push. Then run
`./install.sh` to create the symlink.

Or use a tool like
[`extract-ai-context.sh`](https://github.com/ali5ter/carrybag-lite/blob/main/tools/extract-ai-context.sh)
to automate the full workflow: untrack the file from the public repo, move it here, and symlink it back.
