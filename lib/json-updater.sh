#!/bin/bash
# json-updater.sh - JSON file manipulation utilities
# Handles version updates in package.json and app.json with backup/rollback

# Update version field in JSON file (root level)
update_json_version() {
    local json_file="$1"
    local new_version="$2"

    if [[ ! -f "$json_file" ]]; then
        log_error "Archivo JSON no encontrado: $json_file"
        return 1
    fi

    if ! validate_version "$new_version"; then
        return 1
    fi

    log_info "Actualizando versión en $(basename "$json_file") a ${new_version}"

    # Create backup
    cp "$json_file" "${json_file}.bak"

    # Update version using jq
    local temp_file
    temp_file=$(mktemp)

    if ! jq --indent 2 ".version = \"${new_version}\"" "$json_file" > "$temp_file" 2>/dev/null; then
        log_error "Error al actualizar versión en $json_file"
        # Restore backup
        mv "${json_file}.bak" "$json_file"
        rm -f "$temp_file"
        return 1
    fi

    # Validate the output is valid JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "El JSON resultante es inválido"
        mv "${json_file}.bak" "$json_file"
        rm -f "$temp_file"
        return 1
    fi

    # Apply changes
    mv "$temp_file" "$json_file"
    rm -f "${json_file}.bak"

    log_success "Versión actualizada a ${new_version} en $(basename "$json_file")"
    return 0
}

# Update version in Expo app.json (nested path: expo.version)
update_expo_version() {
    local app_json="$1"
    local new_version="$2"

    if [[ ! -f "$app_json" ]]; then
        log_error "app.json no encontrado: $app_json"
        return 1
    fi

    if ! validate_version "$new_version"; then
        return 1
    fi

    log_info "Actualizando versión Expo en $(basename "$app_json") a ${new_version}"

    # Create backup
    cp "$app_json" "${app_json}.bak"

    # Update expo.version using jq
    local temp_file
    temp_file=$(mktemp)

    if ! jq --indent 2 ".expo.version = \"${new_version}\"" "$app_json" > "$temp_file" 2>/dev/null; then
        log_error "Error al actualizar versión Expo en $app_json"
        # Restore backup
        mv "${app_json}.bak" "$app_json"
        rm -f "$temp_file"
        return 1
    fi

    # Validate the output is valid JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "El JSON resultante es inválido"
        mv "${app_json}.bak" "$app_json"
        rm -f "$temp_file"
        return 1
    fi

    # Apply changes
    mv "$temp_file" "$app_json"
    rm -f "${app_json}.bak"

    log_success "Versión Expo actualizada a ${new_version} en $(basename "$app_json")"
    return 0
}

# Verify version was updated correctly in both files
verify_version_update() {
    local package_json="$1"
    local app_json="$2"
    local expected_version="$3"

    local package_version
    local app_version

    package_version=$(jq -r '.version' "$package_json" 2>/dev/null)
    app_version=$(jq -r '.expo.version' "$app_json" 2>/dev/null)

    if [[ "$package_version" != "$expected_version" ]]; then
        log_error "La versión en package.json ($package_version) no coincide con la esperada ($expected_version)"
        return 1
    fi

    if [[ "$app_version" != "$expected_version" ]]; then
        log_error "La versión en app.json ($app_version) no coincide con la esperada ($expected_version)"
        return 1
    fi

    log_success "Versiones verificadas correctamente: ${expected_version}"
    return 0
}

# Rollback version changes
rollback_version_changes() {
    local package_json="$1"
    local app_json="$2"

    local rolled_back=false

    if [[ -f "${package_json}.bak" ]]; then
        mv "${package_json}.bak" "$package_json"
        log_info "Rollback de package.json completado"
        rolled_back=true
    fi

    if [[ -f "${app_json}.bak" ]]; then
        mv "${app_json}.bak" "$app_json"
        log_info "Rollback de app.json completado"
        rolled_back=true
    fi

    if $rolled_back; then
        log_success "Rollback de cambios de versión completado"
    else
        log_warn "No se encontraron backups para hacer rollback"
    fi
}
