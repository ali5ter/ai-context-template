#!/usr/bin/env bash
# @file install.sh
# @brief Symlink AI context files from this repo into local project directories.
# @description
#   Scans each subdirectory (named after a GitHub repo) and creates a symlink
#   for any AI context file found (CLAUDE.md, AGENTS.md, GEMINI.md) into the
#   corresponding local project directory. Skips repos not found locally.
#
#   Inspired by Dan Maby's article "Managing AI Configuration Files Across
#   Projects": https://www.danmaby.com/posts/2025/08/managing-ai-configuration-files-across-projects/
#
# @author Alister Lewis-Bowen <alister@lewis-bowen.org>
# @version 1.1.0
# @date 2026-04-27
# @license MIT
#
# @usage ./install.sh [--dry-run] [--projects-dir <path>]
#
# @dependencies pfb, git
#
# @exit 0 All symlinks created or already in place
# @exit 1 Invalid arguments

set -euo pipefail

type pfb >/dev/null 2>&1 || {
    echo "error: pfb is required." >&2
    echo "  macOS: brew tap ali5ter/pfb && brew install pfb" >&2
    echo "  Linux: curl -sL https://raw.githubusercontent.com/ali5ter/pfb/main/install.sh | bash" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/repos"
DRY_RUN=false
AI_FILES=(CLAUDE.md AGENTS.md GEMINI.md)
PROJECTS_DIR=""

# @description Returns the platform-appropriate default projects root directory.
# @return Prints the path to stdout
# @example default_projects_dir
default_projects_dir() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$HOME/Documents/Projects"
    else
        echo "$HOME/src"
    fi
}

# @description Creates a symlink for an AI context file into its project directory.
# @param $1 repo_name — name of the repo subdirectory in this repo
# @param $2 ai_file — filename (e.g. CLAUDE.md)
# @param $3 project_dir — full path to the local project directory
# @return 0 on success, 1 if skipped
# @example link_context_file my-repo CLAUDE.md /home/user/src/my-repo
link_context_file() {
    local repo_name="$1" ai_file="$2" project_dir="$3"
    local src="$REPOS_DIR/$repo_name/$ai_file"
    local dst="$project_dir/$ai_file"

    if [[ "$DRY_RUN" == true ]]; then
        pfb info "[dry-run] would symlink: $dst → $src"
        return 0
    fi

    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        pfb subheading "$ai_file already linked"
        return 0
    fi

    if [[ -f "$dst" && ! -L "$dst" ]]; then
        local backup="${dst}.backup.$(date '+%Y%m%d%H%M%S')"
        mv "$dst" "$backup"
        pfb warn "existing $ai_file backed up to $(basename "$backup")"
    fi

    ln -sf "$src" "$dst"
    pfb success "linked $ai_file → $src"
}

# @description Prints usage information and exits.
# @return Exits with code 0
# @example usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--projects-dir <path>]

Options:
  --dry-run              Preview changes without making them
  --projects-dir <path>  Override the default projects root directory
                         (default: ~/Documents/Projects on macOS, ~/src on Linux)
  -h, --help             Show this help and exit
EOF
    exit 0
}

# @description Main entry point.
# @param $@ CLI arguments
# @return 0 on completion
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)       DRY_RUN=true; shift ;;
            --projects-dir)  PROJECTS_DIR="$2"; shift 2 ;;
            -h|--help)       usage ;;
            *)               pfb error "unknown argument: $1"; usage ;;
        esac
    done

    local projects_root="${PROJECTS_DIR:-$(default_projects_dir)}"

    pfb heading "AI Context Installer" "🤖"
    pfb subheading "projects root: $projects_root"
    [[ "$DRY_RUN" == true ]] && pfb warn "dry-run mode — no changes will be made"

    local linked=0 skipped=0

    for repo_dir in "$REPOS_DIR"/*/; do
        [[ -d "$repo_dir" ]] || continue
        local repo_name
        repo_name="$(basename "$repo_dir")"
        local project_dir="$projects_root/$repo_name"

        pfb heading "$repo_name" "📁"

        if [[ ! -d "$project_dir" ]]; then
            pfb warn "no local project found at $project_dir — skipping"
            (( skipped++ )) || true
            continue
        fi

        local found=false
        for ai_file in "${AI_FILES[@]}"; do
            if [[ -f "$repo_dir/$ai_file" ]]; then
                link_context_file "$repo_name" "$ai_file" "$project_dir"
                found=true
                (( linked++ )) || true
            fi
        done

        [[ "$found" == false ]] && pfb warn "no AI context file found in $repo_dir"
    done

    pfb success "done — $linked linked, $skipped skipped (no local clone found)"
}

main "$@"
