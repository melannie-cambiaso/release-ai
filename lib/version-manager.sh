#!/bin/bash
# version-manager.sh - Version extraction and validation utilities
# Handles semantic versioning logic for release automation

# Extract current version from package.json
get_current_version() {
    local package_json="${1:-package.json}"

    if [[ ! -f "$package_json" ]]; then
        log_error "package.json no encontrado: $package_json"
        return 1
    fi

    local version
    version=$(jq -r '.version' "$package_json" 2>/dev/null)

    if [[ -z "$version" || "$version" == "null" ]]; then
        log_error "No se pudo leer la versión de $package_json"
        return 1
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
    tag=$(git describe --tags --abbrev=0 2>/dev/null)

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
get_commits_since_last_tag() {
    local last_tag
    last_tag=$(get_last_release_tag)

    if [[ -z "$last_tag" ]]; then
        # If no tags, get all commits
        git log --no-merges --pretty=format:'%H|%s|%b'
    else
        # Get commits since last tag
        git log "${last_tag}..HEAD" --no-merges --pretty=format:'%H|%s|%b'
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
