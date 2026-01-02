#!/bin/bash
# git-operations.sh - Safe git operation wrappers with error handling
# Provides retry logic and validation for git commands

# Safe checkout with validation
git_safe_checkout() {
    local branch="$1"

    log_info "Cambiando a branch: $branch"

    if ! git checkout "$branch" 2>&1; then
        log_error "Fallo al cambiar a branch: $branch"
        return 1
    fi

    log_success "Branch actual: $branch"
    return 0
}

# Safe pull with conflict detection
git_safe_pull() {
    log_info "Obteniendo últimos cambios..."

    local output
    if ! output=$(git pull 2>&1); then
        log_error "Fallo al hacer pull"
        echo "$output" >&2
        return 1
    fi

    log_success "Cambios obtenidos exitosamente"
    return 0
}

# Safe push with retry logic
git_safe_push() {
    local args="$*"
    local max_retries=3
    local retry_count=0

    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Enviando cambios al remoto... (intento $((retry_count + 1))/$max_retries)"

        if git push $args 2>&1; then
            log_success "Push exitoso"
            return 0
        fi

        retry_count=$((retry_count + 1))

        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Push falló, reintentando en 2 segundos..."
            sleep 2
        fi
    done

    log_error "Fallo al hacer push después de ${max_retries} intentos"
    return 1
}

# Create new branch from current HEAD
git_create_branch() {
    local branch_name="$1"

    # Check if branch already exists locally
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        log_error "El branch ya existe localmente: $branch_name"
        return 1
    fi

    # Check if branch exists remotely
    if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
        log_error "El branch ya existe en el remoto: $branch_name"
        return 1
    fi

    log_info "Creando branch: $branch_name"

    if ! git checkout -b "$branch_name" 2>&1; then
        log_error "Fallo al crear branch: $branch_name"
        return 1
    fi

    log_success "Branch creado: $branch_name"
    return 0
}

# Get commits between two refs
git_get_commits() {
    local from_ref="$1"
    local to_ref="${2:-HEAD}"
    local format="${3:-%H|%an|%ae|%s|%b}"

    git log "${from_ref}..${to_ref}" \
        --no-merges \
        --pretty=format:"$format"
}

# Check if working directory is clean
git_is_clean() {
    if [[ -n $(git status --porcelain) ]]; then
        return 1
    fi
    return 0
}

# Verify we're in a git repository
git_verify_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "No estás en un repositorio git"
        return 1
    fi
    return 0
}

# Get current branch name
git_current_branch() {
    git branch --show-current
}

# Check if branch exists (local or remote)
git_branch_exists() {
    local branch_name="$1"
    local check_remote="${2:-false}"

    # Check local
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        return 0
    fi

    # Check remote if requested
    if [[ "$check_remote" == "true" ]]; then
        if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
            return 0
        fi
    fi

    return 1
}

# Delete branch (local and optionally remote)
git_delete_branch() {
    local branch_name="$1"
    local delete_remote="${2:-false}"

    # Delete local branch
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        log_info "Eliminando branch local: $branch_name"
        git branch -D "$branch_name" 2>&1 || log_warn "No se pudo eliminar branch local"
    fi

    # Delete remote branch if requested
    if [[ "$delete_remote" == "true" ]]; then
        if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
            log_info "Eliminando branch remoto: $branch_name"
            git push origin --delete "$branch_name" 2>&1 || log_warn "No se pudo eliminar branch remoto"
        fi
    fi
}

# Cherry-pick a commit
git_safe_cherry_pick() {
    local commit_hash="$1"

    log_info "Aplicando cherry-pick del commit: ${commit_hash:0:7}"

    if ! git cherry-pick "$commit_hash" 2>&1; then
        log_error "Fallo al hacer cherry-pick del commit: $commit_hash"
        log_info "Puedes continuar manualmente resolviendo conflictos y ejecutando: git cherry-pick --continue"
        return 1
    fi

    log_success "Cherry-pick aplicado exitosamente"
    return 0
}

# Merge branch with strategy
git_safe_merge() {
    local branch_to_merge="$1"
    local strategy="${2:-ours}"
    local commit_message="${3:-}"

    log_info "Mergeando $branch_to_merge con estrategia: $strategy"

    local merge_cmd="git merge \"$branch_to_merge\" -X $strategy --no-edit"

    if [[ -n "$commit_message" ]]; then
        merge_cmd="$merge_cmd -m \"$commit_message\""
    fi

    if ! eval "$merge_cmd" 2>&1; then
        log_error "Fallo al hacer merge de $branch_to_merge"
        return 1
    fi

    log_success "Merge completado exitosamente"
    return 0
}

# Create annotated tag
git_create_tag() {
    local tag_name="$1"
    local tag_message="$2"

    # Check if tag already exists
    if git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
        log_error "El tag ya existe: $tag_name"
        return 1
    fi

    log_info "Creando tag: $tag_name"

    if ! git tag -a "$tag_name" -m "$tag_message" 2>&1; then
        log_error "Fallo al crear tag: $tag_name"
        return 1
    fi

    log_success "Tag creado: $tag_name"
    return 0
}

# Push tags to remote
git_push_tags() {
    log_info "Enviando tags al remoto..."

    if ! git push origin --tags 2>&1; then
        log_error "Fallo al enviar tags"
        return 1
    fi

    log_success "Tags enviados exitosamente"
    return 0
}

# Get commit hash
git_get_commit_hash() {
    local ref="${1:-HEAD}"
    git rev-parse "$ref" 2>/dev/null
}

# Check if gh CLI is authenticated
gh_is_authenticated() {
    if ! gh auth status >/dev/null 2>&1; then
        log_error "gh CLI no está autenticado"
        log_info "Por favor ejecuta: gh auth login"
        return 1
    fi
    return 0
}
