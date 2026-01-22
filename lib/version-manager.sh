#!/bin/bash
# version-manager.sh - Version extraction and validation utilities
# Handles semantic versioning logic for release automation

# Extract current version from various version file formats
# Supports: package.json, VERSION file, or any JSON with .version field
get_current_version() {
    local version_file="${1:-package.json}"

    if [[ ! -f "$version_file" ]]; then
        # Try fallback to VERSION file if default package.json doesn't exist
        if [[ "$version_file" == "package.json" ]] && [[ -f "VERSION" ]]; then
            version_file="VERSION"
        else
            log_error "Archivo de versión no encontrado: $version_file"
            return 1
        fi
    fi

    local version

    # Check if it's a JSON file (package.json, manifest.json, etc.)
    if [[ "$version_file" =~ \.json$ ]]; then
        version=$(jq -r '.version' "$version_file" 2>/dev/null)

        if [[ -z "$version" || "$version" == "null" ]]; then
            log_error "No se pudo leer la versión de $version_file"
            return 1
        fi
    else
        # Plain text version file (VERSION, version.txt, etc.)
        version=$(cat "$version_file" 2>/dev/null | tr -d '[:space:]')

        if [[ -z "$version" ]]; then
            log_error "No se pudo leer la versión de $version_file"
            return 1
        fi
    fi

    echo "$version"
}

# Validate semantic version format (X.Y.Z)
validate_version() {
    local version="$1"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Formato de versión inválido: $version"
        log_error "Esperado: X.Y.Z (ej: 1.8.3)"
        return 1
    fi

    return 0
}

# Compare two semantic versions
# Returns: 0 if v1 < v2, 1 if v1 == v2, 2 if v1 > v2
compare_versions() {
    local v1="$1"
    local v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        return 1
    fi

    local IFS=.
    local i ver1=($v1) ver2=($v2)

    # Compare each component
    for ((i=0; i<3; i++)); do
        local num1=${ver1[i]:-0}
        local num2=${ver2[i]:-0}

        if [[ $num1 -lt $num2 ]]; then
            return 0
        elif [[ $num1 -gt $num2 ]]; then
            return 2
        fi
    done

    return 1
}

# Get last release tag from git
get_last_release_tag() {
    local tag

    # Try git describe first (works if there's a tag in current branch history)
    tag=$(git describe --tags --abbrev=0 2>/dev/null)

    # If git describe fails, look for version bump commits in current branch
    # This handles workflows where tags are in main but version bumps are cherry-picked to develop
    if [[ -z "$tag" ]]; then
        local version_commit=$(git log --no-merges --grep="^chore(release): bump version to" --format="%s" -1 2>/dev/null)
        if [[ -n "$version_commit" ]]; then
            # Extract version from commit message: "chore(release): bump version to 1.8.2" -> "v1.8.2"
            local version=$(echo "$version_commit" | sed -n 's/^chore(release): bump version to \([0-9.]*\)$/\1/p')
            if [[ -n "$version" ]]; then
                tag="v${version}"
            fi
        fi
    fi

    # If still no tag found, try to find the most recent tag that is an ancestor of HEAD
    if [[ -z "$tag" ]]; then
        tag=$(git tag --sort=-committerdate | while read -r t; do
            if git merge-base --is-ancestor "$t" HEAD 2>/dev/null; then
                echo "$t"
                break
            fi
        done)
    fi

    if [[ -z "$tag" ]]; then
        log_warn "No se encontraron tags previos"
        return 1
    fi

    echo "$tag"
}

# Extract version from tag (removes 'v' prefix if present)
extract_version_from_tag() {
    local tag="$1"
    echo "$tag" | sed 's/^v//'
}

# Calculate next version based on bump type
# Args: current_version bump_type(major|minor|patch)
calculate_next_version() {
    local current="$1"
    local bump_type="${2:-patch}"

    if ! validate_version "$current"; then
        return 1
    fi

    local IFS=.
    read -ra parts <<< "$current"
    local major="${parts[0]}"
    local minor="${parts[1]}"
    local patch="${parts[2]}"

    case "$bump_type" in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "${major}.$((minor + 1)).0"
            ;;
        patch)
            echo "${major}.${minor}.$((patch + 1))"
            ;;
        *)
            log_error "Tipo de bump inválido: $bump_type"
            log_error "Esperado: major, minor, o patch"
            return 1
            ;;
    esac
}

# Get commits since last tag
# Args: end_ref (optional) - commit/ref to use as end point (default: HEAD)
get_commits_since_last_tag() {
    local end_ref="${1:-HEAD}"
    local last_tag
    last_tag=$(get_last_release_tag)

    if [[ -z "$last_tag" ]]; then
        # If no tags, get all commits up to end_ref
        if [[ "$end_ref" == "HEAD" ]]; then
            git log --no-merges --pretty=format:'%H|%s|%b'
        else
            git log --no-merges --pretty=format:'%H|%s|%b' "${end_ref}"
        fi
        return
    fi

    # Extract version from tag
    local version=$(echo "$last_tag" | sed 's/^v//')

    # Always look for version bump commit first in develop branch (more accurate for develop branch workflow)
    local bump_commit=""

    # Use configured develop branch or default to "develop"
    local dev_branch="${DEVELOP_BRANCH:-develop}"

    # Check if develop branch exists locally or remotely
    if git rev-parse --verify "$dev_branch" &>/dev/null; then
        bump_commit=$(git log "$dev_branch" --no-merges --grep="^chore(release): bump version to ${version}" --format="%H" -1 2>/dev/null)
        if [[ -n "${DEBUG:-}" ]] && [[ -n "$bump_commit" ]]; then
            echo "[DEBUG] Found bump commit in local $dev_branch: ${bump_commit:0:7}" >&2
        fi
    elif git rev-parse --verify "origin/$dev_branch" &>/dev/null; then
        bump_commit=$(git log "origin/$dev_branch" --no-merges --grep="^chore(release): bump version to ${version}" --format="%H" -1 2>/dev/null)
        if [[ -n "${DEBUG:-}" ]] && [[ -n "$bump_commit" ]]; then
            echo "[DEBUG] Found bump commit in origin/$dev_branch: ${bump_commit:0:7}" >&2
        fi
    fi

    # If not found in develop, try current branch
    if [[ -z "$bump_commit" ]]; then
        bump_commit=$(git log --no-merges --grep="^chore(release): bump version to ${version}" --format="%H" -1 2>/dev/null)
        if [[ -n "${DEBUG:-}" ]] && [[ -n "$bump_commit" ]]; then
            echo "[DEBUG] Found bump commit in current branch: ${bump_commit:0:7}" >&2
        fi
    fi

    if [[ -n "${DEBUG:-}" ]]; then
        if [[ -z "$bump_commit" ]]; then
            echo "[DEBUG] No bump commit found for version $version, will use tag $last_tag" >&2
        fi
    fi

    if [[ -n "$bump_commit" ]]; then
        # Found version bump commit, use it as reference point
        git log --no-merges --pretty=format:'%H|%s|%b' "${bump_commit}..${end_ref}"
    elif git rev-parse "$last_tag" &>/dev/null; then
        # Fallback: use the tag directly
        git log --no-merges --pretty=format:'%H|%s|%b' "${last_tag}..${end_ref}"
    else
        # Last resort: get all commits up to end_ref
        if [[ "$end_ref" == "HEAD" ]]; then
            git log --no-merges --pretty=format:'%H|%s|%b'
        else
            git log --no-merges --pretty=format:'%H|%s|%b' "${end_ref}"
        fi
    fi
}

# Parse commit type from conventional commit message
# Example: "feat(scope): message" -> "feat"
parse_commit_type() {
    local commit_message="$1"

    # Extract type from conventional commit format
    if [[ "$commit_message" =~ ^([a-z]+)(\(.+\))?!?: ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

# Check if commit has breaking change
has_breaking_change() {
    local commit_subject="$1"
    local commit_body="$2"

    # Check for ! in type (e.g., "feat!:")
    if [[ "$commit_subject" =~ ^[a-z]+(\(.+\))?!: ]]; then
        return 0
    fi

    # Check for "BREAKING CHANGE:" in body
    if [[ "$commit_body" =~ BREAKING[[:space:]]CHANGE: ]]; then
        return 0
    fi

    return 1
}
