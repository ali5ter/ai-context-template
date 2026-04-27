#!/usr/bin/env bash
# @file extract-ai-context.sh
# @brief Move AI context files from a public repo into this private ai-context repo.
# @description
#   Given a path to a local git repository, finds all AI context files
#   (CLAUDE.md, AGENTS.md, GEMINI.md), removes them from git tracking,
#   adds them to .gitignore, moves them into this repo under a subdirectory
#   named after the source repo, then symlinks them back. Both repos are
#   committed and pushed.
#
#   Run this script from within the ai-context repo clone.
#
#   Inspired by Dan Maby's article "Managing AI Configuration Files Across
#   Projects": https://www.danmaby.com/posts/2025/08/managing-ai-configuration-files-across-projects/
#
# @author Alister Lewis-Bowen <alister@lewis-bowen.org>
# @version 1.1.0
# @date 2026-04-27
# @license MIT
#
# @usage ./extract-ai-context.sh <path-to-repo>
#
# @dependencies pfb, gh, git
#
# @exit 0 Success
# @exit 1 Missing argument or invalid repo path
# @exit 2 No AI context files found in target repo

set -euo pipefail

type pfb >/dev/null 2>&1 || {
    echo "error: pfb is required." >&2
    echo "  macOS: brew tap ali5ter/pfb && brew install pfb" >&2
    echo "  Linux: curl -sL https://raw.githubusercontent.com/ali5ter/pfb/main/install.sh | bash" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_FILES=(CLAUDE.md AGENTS.md GEMINI.md)

# @description Untracks all given AI context files from git and commits .gitignore.
# @param $1 repo_path — absolute path to the target repo
# @param $@ ai_files — one or more filenames to untrack
# @return 0 on success
# @example untrack_from_repo /path/to/repo CLAUDE.md AGENTS.md
untrack_from_repo() {
    local repo_path="$1"; shift
    local files=("$@")

    pfb heading "Updating target repo" "📝"

    local gitignore="$repo_path/.gitignore"
    for ai_file in "${files[@]}"; do
        git -C "$repo_path" rm --cached "$ai_file"
        pfb success "removed $ai_file from git index"

        if ! grep -qxF "$ai_file" "$gitignore" 2>/dev/null; then
            echo "$ai_file" >> "$gitignore"
            pfb success "added $ai_file to .gitignore"
        else
            pfb subheading "$ai_file already in .gitignore"
        fi
    done

    local file_list="${files[*]}"
    git -C "$repo_path" add .gitignore
    git -C "$repo_path" commit -m "chore: remove ${file_list// /, } from tracking, add to .gitignore"
    pfb success "committed .gitignore update"
}

# @description Copies all AI context files into this repo and commits them.
# @param $1 repo_name — name of the source repo (used as subdirectory)
# @param $2 src_dir_path — directory containing the source files
# @param $@ ai_files — one or more filenames to copy
# @return 0 on success
# @example store_in_this_repo my-repo /path/to/repo CLAUDE.md AGENTS.md
store_in_this_repo() {
    local repo_name="$1" src_dir_path="$2"; shift 2
    local files=("$@")
    local dest_dir="$SCRIPT_DIR/$repo_name"

    pfb heading "Storing in ai-context repo" "💾"

    mkdir -p "$dest_dir"
    for ai_file in "${files[@]}"; do
        cp "$src_dir_path/$ai_file" "$dest_dir/$ai_file"
        pfb success "copied $ai_file to $dest_dir/"
        git -C "$SCRIPT_DIR" add "$repo_name/$ai_file"
    done

    local file_list="${files[*]}"
    git -C "$SCRIPT_DIR" commit -m "feat($repo_name): add AI context file(s) ${file_list// /, }"
    git -C "$SCRIPT_DIR" push
    pfb success "pushed"
}

# @description Creates symlinks in the target repo pointing to files in this repo.
# @param $1 repo_path — directory where symlinks should be created
# @param $2 dest_dir — subdirectory in this repo holding the files
# @param $@ ai_files — one or more filenames to symlink
# @return 0 on success
# @example create_symlinks /path/to/repo /path/to/ai-context/repo CLAUDE.md AGENTS.md
create_symlinks() {
    local repo_path="$1" dest_dir="$2"; shift 2
    local files=("$@")

    pfb heading "Creating symlinks" "🔗"

    for ai_file in "${files[@]}"; do
        local target="$repo_path/$ai_file"
        local source="$dest_dir/$ai_file"

        if [[ -f "$target" && ! -L "$target" ]]; then
            local backup="${target}.backup.$(date '+%Y%m%d%H%M%S')"
            mv "$target" "$backup"
            pfb warn "$ai_file backed up to $(basename "$backup")"
        fi

        ln -sf "$source" "$target"
        pfb success "$ai_file → $source"
    done
}

# @description Pushes any outstanding changes in the target repo.
# @param $1 repo_path — absolute path to the target repo
# @return 0 on success
# @example push_target_repo /path/to/repo
push_target_repo() {
    local repo_path="$1"

    pfb heading "Pushing target repo" "🚀"

    if git -C "$repo_path" push 2>&1; then
        pfb success "pushed"
    else
        pfb warn "push failed — you may need to push manually"
    fi
}

# @description Main entry point.
# @param $1 path — path to the local git repository to process
# @return 0 on success
# @example ./extract-ai-context.sh /path/to/my-public-repo
main() {
    if [[ $# -lt 1 ]]; then
        pfb error "usage: $(basename "$0") <path-to-repo>"
        exit 1
    fi

    local repo_path
    repo_path="$(cd "$1" && pwd)"

    if [[ ! -d "$repo_path/.git" ]]; then
        pfb error "$repo_path is not a git repository"
        exit 1
    fi

    local repo_name
    repo_name="$(basename "$repo_path")"

    pfb heading "extract-ai-context" "🤖"
    pfb subheading "target: $repo_path"

    local found_files=()
    local already_linked=()
    for candidate in "${AI_FILES[@]}"; do
        if [[ -L "$repo_path/$candidate" ]]; then
            already_linked+=("$candidate")
        elif [[ -f "$repo_path/$candidate" ]]; then
            found_files+=("$candidate")
        fi
    done

    for f in "${already_linked[@]+"${already_linked[@]}"}"; do
        pfb warn "$f is already a symlink — skipping"
    done

    if [[ ${#found_files[@]} -eq 0 ]]; then
        if [[ ${#already_linked[@]} -gt 0 ]]; then
            pfb info "all AI context files already extracted"
            exit 0
        fi
        pfb error "no AI context files found in $repo_path (looked for: ${AI_FILES[*]})"
        exit 2
    fi

    pfb info "found: ${found_files[*]}"

    untrack_from_repo "$repo_path" "${found_files[@]}"
    store_in_this_repo "$repo_name" "$repo_path" "${found_files[@]}"
    create_symlinks "$repo_path" "$SCRIPT_DIR/$repo_name" "${found_files[@]}"
    push_target_repo "$repo_path"

    pfb heading "Done" "✅"
    pfb subheading "run './install.sh' on any new machine after cloning this repo to restore symlinks"
}

main "$@"
