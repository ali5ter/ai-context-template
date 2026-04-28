#!/usr/bin/env bash
# @file extract-ai-context.sh
# @brief Move AI context files from public repos into this private ai-context repo.
# @description
#   Single mode: given a path to a git repository, finds all AI context files
#   (CLAUDE.md, AGENTS.md, GEMINI.md), removes them from git tracking, adds them
#   to .gitignore, copies them here, and symlinks them back.
#
#   Batch mode: given a directory (or no argument), scans every subdirectory for
#   git repos that contain unextracted AI context files and processes them all.
#   Use --parallel to untrack and copy repos concurrently.
#
#   Inspired by Dan Maby's article "Managing AI Configuration Files Across
#   Projects": https://www.danmaby.com/posts/2025/08/managing-ai-configuration-files-across-projects/
#
# @author Alister Lewis-Bowen <alister@lewis-bowen.org>
# @version 2.0.0
# @date 2026-04-27
# @license MIT
#
# @usage ./extract-ai-context.sh [--parallel] [-q] [<path>]
#
# @dependencies pfb, git
#
# @exit 0 Success
# @exit 1 Invalid argument or not a git repo (single mode)
# @exit 2 No AI context files found (single mode)

set -euo pipefail

type pfb >/dev/null 2>&1 || {
    echo "error: pfb is required." >&2
    echo "  macOS: brew tap ali5ter/pfb && brew install pfb" >&2
    echo "  Linux: curl -sL https://raw.githubusercontent.com/ali5ter/pfb/main/install.sh | bash" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/repos"
AI_FILES=(CLAUDE.md AGENTS.md GEMINI.md)
PARALLEL=false
QUIET=false
UPDATE_MAX_JOBS="${UPDATE_MAX_JOBS:-8}"

# @description Returns the platform-appropriate default projects root directory.
# @return Prints the path to stdout
# @example default_projects_dir
default_projects_dir() {
    [[ "$OSTYPE" == "darwin"* ]] && echo "$HOME/Documents/Projects" || echo "$HOME/src"
}

# @description Prints usage information and exits.
# @return Exits with code 0
# @example usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [<path>]

  <path>  A git repository (single mode) or a directory of repositories (batch
          mode). Defaults to $(default_projects_dir).

Options:
  --parallel         Process repos concurrently in batch mode
  -q, --quiet        Suppress output for repos with no AI context files
  -h, --help         Show this help and exit

Environment:
  UPDATE_MAX_JOBS    Max parallel workers (default: 8)
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Silent helper functions — no pfb, called from both modes
# ---------------------------------------------------------------------------

# @description Removes AI context files from a repo's git index and commits .gitignore.
# @param $1 repo_path
# @param $@ ai_files
# @return Non-zero on git failure
# @example _untrack /path/to/repo CLAUDE.md
_untrack() {
    local repo_path="$1"; shift
    local files=("$@")
    local gitignore="$repo_path/.gitignore"
    for ai_file in "${files[@]}"; do
        git -C "$repo_path" rm --cached "$ai_file"
        if ! grep -qxF "$ai_file" "$gitignore" 2>/dev/null; then
            [[ -s "$gitignore" ]] && [[ $(tail -c1 "$gitignore" | wc -l) -eq 0 ]] && printf '\n' >> "$gitignore"
            echo "$ai_file" >> "$gitignore"
        fi
    done
    local file_list="${files[*]}"
    git -C "$repo_path" add .gitignore
    git -C "$repo_path" commit -m "chore: remove ${file_list// /, } from tracking, add to .gitignore"
}

# @description Copies AI context files into this repo under a named subdirectory.
# @param $1 repo_name
# @param $2 src_dir
# @param $@ ai_files
# @example _copy_here my-repo /path/to/repo CLAUDE.md
_copy_here() {
    local repo_name="$1" src_dir="$2"; shift 2
    local files=("$@")
    local dest_dir="$REPOS_DIR/$repo_name"
    mkdir -p "$dest_dir"
    for ai_file in "${files[@]}"; do cp "$src_dir/$ai_file" "$dest_dir/$ai_file"; done
}

# @description Stages and commits AI context files for one repo into this repo.
# @param $1 repo_name
# @param $@ ai_files
# @example _commit_here my-repo CLAUDE.md
_commit_here() {
    local repo_name="$1"; shift
    local files=("$@")
    local file_list="${files[*]}"
    git -C "$SCRIPT_DIR" add "repos/$repo_name/"
    git -C "$SCRIPT_DIR" commit -m "feat($repo_name): add AI context file(s) ${file_list// /, }"
}

# @description Creates symlinks in a target repo pointing back to files in this repo.
# Backs up any regular file that would be displaced.
# @param $1 repo_path
# @param $2 dest_dir (subdirectory path in this repo)
# @param $@ ai_files
# @example _symlink /path/to/repo /path/to/ai-context/my-repo CLAUDE.md
_symlink() {
    local repo_path="$1" dest_dir="$2"; shift 2
    local files=("$@")
    for ai_file in "${files[@]}"; do
        local target="$repo_path/$ai_file" source="$dest_dir/$ai_file"
        if [[ -f "$target" && ! -L "$target" ]]; then
            mv "$target" "${target}.backup.$(date '+%Y%m%d%H%M%S')"
        fi
        ln -sf "$source" "$target"
    done
}

# ---------------------------------------------------------------------------
# Batch mode worker
# ---------------------------------------------------------------------------
# Result file format (written by process_repo_worker):
#   Line 1: ok | failed | skipped
#   Line 2: human-readable message
#   Line 3: space-separated filenames (only present when status=ok)

# @description Validates, untracks, and copies files for one repo. Silent.
# @param $1 repo_path
# @param $2 outfile — path to write the result record
# @example process_repo_worker /path/to/repo /tmp/result.XXX
process_repo_worker() {
    local repo_path="$1" outfile="$2"

    if [[ ! -d "$repo_path/.git" ]]; then
        printf 'skipped\nnot a git repository\n' > "$outfile"
        return 0
    fi

    local repo_name found_files=() already_linked=()
    repo_name="$(basename "$repo_path")"

    for candidate in "${AI_FILES[@]}"; do
        if   [[ -L "$repo_path/$candidate" ]]; then already_linked+=("$candidate")
        elif [[ -f "$repo_path/$candidate" ]]; then found_files+=("$candidate")
        fi
    done

    if [[ ${#found_files[@]} -eq 0 ]]; then
        local msg="no AI context files"
        [[ ${#already_linked[@]} -gt 0 ]] && msg="already extracted"
        printf 'skipped\n%s\n' "$msg" > "$outfile"
        return 0
    fi

    local file_list="${found_files[*]}"
    if ! _untrack "$repo_path" "${found_files[@]}" >/dev/null 2>&1; then
        printf 'failed\nfailed to untrack files from git index\n' > "$outfile"
        return 0
    fi

    _copy_here "$repo_name" "$repo_path" "${found_files[@]}"
    printf 'ok\nextracted: %s\n%s\n' "$file_list" "$file_list" > "$outfile"
}

# @description Displays one batch result and pushes the target repo if ok.
# @param $1 repo_name
# @param $2 repo_path
# @param $3 outfile — result file written by process_repo_worker (deleted on read)
# @side_effects Increments count_ok / count_skipped / count_failed
display_result() {
    local repo="$1" repo_path="$2" outfile="$3"
    local status message
    status=$(sed -n '1p' "$outfile")
    message=$(sed -n '2p' "$outfile")
    rm -f "$outfile"

    case "$status" in
        ok)
            pfb heading "$repo" "📦"
            pfb success "$message"
            if git -C "$repo_path" push >/dev/null 2>&1; then
                pfb success "pushed"
            else
                pfb warn "push failed — push manually"
            fi
            count_ok=$(( count_ok + 1 ))
            ;;
        skipped)
            $QUIET || { pfb heading "$repo" "📦"; pfb info "$message"; }
            count_skipped=$(( count_skipped + 1 ))
            ;;
        failed)
            pfb heading "$repo" "📦"
            pfb error "$message"
            count_failed=$(( count_failed + 1 ))
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Single-repo mode (original verbose behaviour, unchanged)
# ---------------------------------------------------------------------------

# @description Processes one git repository with full pfb progress output.
# @param $1 repo_path — path to a git repository
# @return Exits 1 if not a repo, 2 if no AI context files found
# @example single_mode /path/to/my-repo
single_mode() {
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

    local found_files=() already_linked=()
    for candidate in "${AI_FILES[@]}"; do
        if   [[ -L "$repo_path/$candidate" ]]; then already_linked+=("$candidate")
        elif [[ -f "$repo_path/$candidate" ]]; then found_files+=("$candidate")
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

    pfb heading "Updating target repo" "📝"
    local gitignore="$repo_path/.gitignore"
    for ai_file in "${found_files[@]}"; do
        git -C "$repo_path" rm --cached "$ai_file"
        pfb success "removed $ai_file from git index"
        if ! grep -qxF "$ai_file" "$gitignore" 2>/dev/null; then
            echo "$ai_file" >> "$gitignore"
            pfb success "added $ai_file to .gitignore"
        else
            pfb subheading "$ai_file already in .gitignore"
        fi
    done
    local file_list="${found_files[*]}"
    git -C "$repo_path" add .gitignore
    git -C "$repo_path" commit -m "chore: remove ${file_list// /, } from tracking, add to .gitignore"
    pfb success "committed .gitignore update"

    pfb heading "Storing in ai-context repo" "💾"
    local dest_dir="$REPOS_DIR/$repo_name"
    _copy_here "$repo_name" "$repo_path" "${found_files[@]}"
    for ai_file in "${found_files[@]}"; do pfb success "copied $ai_file to $dest_dir/"; done
    _commit_here "$repo_name" "${found_files[@]}"
    git -C "$SCRIPT_DIR" push
    pfb success "pushed"

    pfb heading "Creating symlinks" "🔗"
    for ai_file in "${found_files[@]}"; do
        local target="$repo_path/$ai_file" source="$dest_dir/$ai_file"
        if [[ -f "$target" && ! -L "$target" ]]; then
            local backup="${target}.backup.$(date '+%Y%m%d%H%M%S')"
            mv "$target" "$backup"
            pfb warn "$ai_file backed up to $(basename "$backup")"
        fi
        ln -sf "$source" "$target"
        pfb success "$ai_file → $source"
    done

    pfb heading "Pushing target repo" "🚀"
    if git -C "$repo_path" push 2>&1; then
        pfb success "pushed"
    else
        pfb warn "push failed — you may need to push manually"
    fi

    pfb heading "Done" "✅"
    pfb subheading "run './install.sh' on any new machine after cloning this repo to restore symlinks"
}

# ---------------------------------------------------------------------------
# Batch mode
# ---------------------------------------------------------------------------

# @description Scans a directory for git repos and extracts AI context files.
# @param $1 scan_dir — directory containing repo subdirectories
# @example batch_mode ~/Documents/Projects
batch_mode() {
    local scan_dir="$1"
    local this_repo_name
    this_repo_name="$(basename "$SCRIPT_DIR")"

    pfb heading "extract-ai-context" "🤖"
    pfb subheading "scanning: $scan_dir"
    $PARALLEL && pfb info "parallel mode (up to ${UPDATE_MAX_JOBS} workers)"

    declare -a candidates=()
    for dir in "$scan_dir"/*/; do
        [[ -d "$dir" ]] || continue
        [[ "$(basename "${dir%/}")" == "$this_repo_name" ]] && continue
        candidates+=("${dir%/}")
    done

    local total=${#candidates[@]}
    pfb subheading "$total directories to check"

    declare -a repo_order=()
    declare -A job_files=()
    declare -A repo_paths=()
    local completed=0

    # Phase 1 — untrack and copy (parallel or sequential)
    if $PARALLEL; then
        for repo_path in "${candidates[@]}"; do
            local repo
            repo="$(basename "$repo_path")"
            local outfile
            outfile="$(mktemp)"
            repo_order+=("$repo")
            job_files["$repo"]="$outfile"
            repo_paths["$repo"]="$repo_path"

            while [[ $(jobs -r | wc -l) -ge $UPDATE_MAX_JOBS ]]; do
                wait -n 2>/dev/null || true
                completed=$(( completed + 1 ))
                pfb progress "$completed" "$total" "Scanning repositories"
            done
            process_repo_worker "$repo_path" "$outfile" &
        done

        while [[ $(jobs -r | wc -l) -gt 0 ]]; do
            wait -n 2>/dev/null || true
            completed=$(( completed + 1 ))
            pfb progress "$completed" "$total" "Scanning repositories"
        done

        if type cursor_up &>/dev/null; then cursor_up >&2; erase_line >&2; fi
        pfb success "All $total repositories scanned"
    else
        for repo_path in "${candidates[@]}"; do
            local repo
            repo="$(basename "$repo_path")"
            local outfile
            outfile="$(mktemp)"
            repo_order+=("$repo")
            job_files["$repo"]="$outfile"
            repo_paths["$repo"]="$repo_path"
            process_repo_worker "$repo_path" "$outfile"
        done
    fi

    # Phase 2 — commit and push this repo once per extracted repo, then one push
    pfb heading "Updating ai-context repo" "💾"
    local committed=0
    for repo in "${repo_order[@]}"; do
        [[ "$(sed -n '1p' "${job_files[$repo]}")" == "ok" ]] || continue
        local files_str
        files_str=$(sed -n '3p' "${job_files[$repo]}")
        read -ra files <<< "$files_str"
        _commit_here "$repo" "${files[@]}" >/dev/null 2>&1
        pfb success "committed $repo (${files[*]})"
        committed=$(( committed + 1 ))
    done

    if [[ $committed -gt 0 ]]; then
        git -C "$SCRIPT_DIR" push
        pfb success "pushed ($committed repos)"
    else
        pfb info "nothing new to commit"
    fi

    # Phase 3 — create symlinks for all successfully extracted repos
    pfb heading "Creating symlinks" "🔗"
    for repo in "${repo_order[@]}"; do
        [[ "$(sed -n '1p' "${job_files[$repo]}")" == "ok" ]] || continue
        local files_str
        files_str=$(sed -n '3p' "${job_files[$repo]}")
        read -ra files <<< "$files_str"
        local repo_path="${repo_paths[$repo]}"
        for ai_file in "${files[@]}"; do
            local target="$repo_path/$ai_file" source="$REPOS_DIR/$repo/$ai_file"
            if [[ -f "$target" && ! -L "$target" ]]; then
                mv "$target" "${target}.backup.$(date '+%Y%m%d%H%M%S')"
                pfb warn "$repo/$ai_file backed up"
            fi
            ln -sf "$source" "$target"
            pfb success "$repo/$ai_file → $source"
        done
    done

    # Phase 4 — display results and push each target repo
    count_ok=0; count_skipped=0; count_failed=0
    for repo in "${repo_order[@]}"; do
        display_result "$repo" "${repo_paths[$repo]}" "${job_files[$repo]}"
    done

    pfb heading "Summary" "📊"
    [[ $count_ok      -gt 0 ]] && pfb success "$count_ok extracted"
    [[ $count_skipped -gt 0 ]] && pfb info    "$count_skipped skipped"
    [[ $count_failed  -gt 0 ]] && pfb error   "$count_failed failed"
    pfb subheading "run './install.sh' on any new machine after cloning this repo to restore symlinks"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# @description Main entry point — routes to single or batch mode.
# @param $@ CLI arguments
# @return 0 on completion
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parallel)  PARALLEL=true; shift ;;
            -q|--quiet)  QUIET=true; shift ;;
            -h|--help)   usage ;;
            -*)          pfb error "unknown option: $1"; usage ;;
            *)           break ;;
        esac
    done

    local target="${1:-$(default_projects_dir)}"

    if [[ -d "$target/.git" ]]; then
        single_mode "$target"
    elif [[ -d "$target" ]]; then
        batch_mode "$target"
    else
        pfb error "path not found: $target"
        exit 1
    fi
}

main "$@"
