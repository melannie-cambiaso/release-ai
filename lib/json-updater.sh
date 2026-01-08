#!/bin/bash
# json-updater.sh - File manipulation utilities for version updates
# Handles version updates in JSON files, plain text VERSION files, and script files

# Generic function to update version in any file based on type
update_version_in_file() {
    local file_path="$1"
    local field="$2"
    local new_version="$3"

    if [[ ! -f "$file_path" ]]; then
        log_warn "Archivo no encontrado, se omite: $file_path"
        return 0
    fi

    if ! validate_version "$new_version"; then
        return 1
    fi

    local file_ext="${file_path##*.}"
    local basename_file=$(basename "$file_path")

    # Determine file type and use appropriate update method
    case "$file_ext" in
        json)
            update_json_field "$file_path" "$field" "$new_version"
            ;;
        js)
            # JavaScript config files (e.g., app.config.js)
            update_js_config_field "$file_path" "$field" "$new_version"
            ;;
        *)
            # Plain text VERSION file or similar
            if [[ "$basename_file" == "VERSION" ]] || [[ -z "$field" ]]; then
                update_plain_version_file "$file_path" "$new_version"
            else
                log_error "Tipo de archivo no soportado: $file_path"
                return 1
            fi
            ;;
    esac
}

# Update a field in a JSON file (supports nested paths like "expo.version")
update_json_field() {
    local json_file="$1"
    local field_path="$2"
    local new_version="$3"

    log_info "Actualizando ${field_path} en $(basename "$json_file") a ${new_version}"

    # Create backup
    cp "$json_file" "${json_file}.bak"

    # Update field using jq
    local temp_file
    temp_file=$(mktemp)

    if ! jq --indent 2 ".${field_path} = \"${new_version}\"" "$json_file" > "$temp_file" 2>/dev/null; then
        log_error "Error al actualizar ${field_path} en $json_file"
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

    log_success "Campo ${field_path} actualizado a ${new_version} en $(basename "$json_file")"
    return 0
}

# Update version in a JavaScript config file (e.g., app.config.js)
update_js_config_field() {
    local js_file="$1"
    local field_path="$2"
    local new_version="$3"

    log_info "Actualizando ${field_path} en $(basename "$js_file") a ${new_version}"

    # Create backup
    cp "$js_file" "${js_file}.bak"

    # Convert nested field path to sed pattern
    # e.g., "expo.version" -> find "version: " within expo object
    local field_name="${field_path##*.}"  # Get last part after last dot

    # Detect OS for sed compatibility
    local sed_inplace_flag
    if [[ "$(uname)" == "Darwin" ]]; then
        sed_inplace_flag="-i ''"
    else
        sed_inplace_flag="-i"
    fi

    # Multiple patterns to handle different JS formats:
    # version: '1.0.0' or version: "1.0.0" or version: `1.0.0`
    # "version": "1.0.0" or 'version': '1.0.0'
    local patterns=(
        "s/\(${field_name}:[[:space:]]*['\"\`]\)[^'\"]*\(['\"\`]\)/\1${new_version}\2/g"
        "s/\(['\"]${field_name}['\"]:[[:space:]]*['\"\`]\)[^'\"]*\(['\"\`]\)/\1${new_version}\2/g"
    )

    local updated=false
    for pattern in "${patterns[@]}"; do
        if grep -q "${field_name}" "$js_file"; then
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' "$pattern" "$js_file" 2>/dev/null && updated=true
            else
                sed -i "$pattern" "$js_file" 2>/dev/null && updated=true
            fi
        fi
    done

    if $updated; then
        rm -f "${js_file}.bak"
        log_success "Campo ${field_path} actualizado a ${new_version} en $(basename "$js_file")"
        return 0
    else
        # Restore backup on failure
        mv "${js_file}.bak" "$js_file"
        log_error "Error al actualizar ${field_path} en $js_file"
        return 1
    fi
}

# Update plain text VERSION file
update_plain_version_file() {
    local version_file="$1"
    local new_version="$2"

    log_info "Actualizando $(basename "$version_file") a ${new_version}"

    # Create backup
    cp "$version_file" "${version_file}.bak"

    # Simply write the new version
    if echo "$new_version" > "$version_file"; then
        rm -f "${version_file}.bak"
        log_success "Versión actualizada a ${new_version} en $(basename "$version_file")"
        return 0
    else
        # Restore backup on failure
        mv "${version_file}.bak" "$version_file"
        log_error "Error al actualizar $version_file"
        return 1
    fi
}

# Update all version files specified in config
update_all_version_files() {
    local new_version="$1"
    local version_files_json="$2"  # JSON array from config
    local updated_files=()
    local failed_files=()

    # Parse version_files array and update each file
    local file_count
    file_count=$(echo "$version_files_json" | jq 'length' 2>/dev/null)

    if [[ -z "$file_count" ]] || [[ "$file_count" == "null" ]] || [[ "$file_count" -eq 0 ]]; then
        log_warn "No se especificaron archivos de versión en la configuración"
        return 1
    fi

    log_info "Actualizando $file_count archivo(s) de versión..."

    for ((i=0; i<file_count; i++)); do
        local file_path
        local field

        file_path=$(echo "$version_files_json" | jq -r ".[$i].path" 2>/dev/null)
        field=$(echo "$version_files_json" | jq -r ".[$i].field" 2>/dev/null)

        if [[ -z "$file_path" ]] || [[ "$file_path" == "null" ]]; then
            log_warn "Entrada de version_files inválida en índice $i"
            continue
        fi

        # Make path absolute if relative
        if [[ ! "$file_path" =~ ^/ ]]; then
            file_path="${REPO_ROOT}/${file_path}"
        fi

        if update_version_in_file "$file_path" "$field" "$new_version"; then
            updated_files+=("$file_path")
        else
            failed_files+=("$file_path")
        fi
    done

    # Report results
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        log_error "Fallaron ${#failed_files[@]} actualizaciones de archivos"
        for file in "${failed_files[@]}"; do
            log_error "  - $file"
        done
        return 1
    fi

    log_success "Todos los archivos de versión actualizados correctamente (${#updated_files[@]})"
    return 0
}

# Verify version was updated correctly in all configured files
verify_all_version_updates() {
    local expected_version="$1"
    local version_files_json="$2"
    local verification_failed=false

    local file_count
    file_count=$(echo "$version_files_json" | jq 'length' 2>/dev/null)

    for ((i=0; i<file_count; i++)); do
        local file_path
        local field

        file_path=$(echo "$version_files_json" | jq -r ".[$i].path" 2>/dev/null)
        field=$(echo "$version_files_json" | jq -r ".[$i].field" 2>/dev/null)

        # Make path absolute if relative
        if [[ ! "$file_path" =~ ^/ ]]; then
            file_path="${REPO_ROOT}/${file_path}"
        fi

        if [[ ! -f "$file_path" ]]; then
            log_warn "Archivo no encontrado para verificación: $file_path"
            continue
        fi

        local actual_version
        local file_ext="${file_path##*.}"
        local basename_file=$(basename "$file_path")

        # Get version based on file type
        # Check if field is empty or null (plain text file)
        if [[ -z "$field" ]] || [[ "$field" == "null" ]]; then
            # Plain text file
            actual_version=$(cat "$file_path" | tr -d '\n\r' | xargs)
        else
            case "$file_ext" in
                json)
                    actual_version=$(jq -r ".${field}" "$file_path" 2>/dev/null)
                    ;;
                js)
                    # Extract version from JS file - try multiple patterns
                    local field_name="${field##*.}"
                    # Try different patterns for JS files
                    actual_version=$(grep -E "${field_name}['\"]?:[[:space:]]*['\"\`]" "$file_path" 2>/dev/null | grep -oE "['\"\`][0-9]+\.[0-9]+\.[0-9]+['\"\`]" | tr -d "'\"\`" | head -1)

                    # If not found, try simpler pattern
                    if [[ -z "$actual_version" ]]; then
                        actual_version=$(grep -oE "${field_name}:[[:space:]]*['\"\`][^'\"]*['\"\`]" "$file_path" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
                    fi
                    ;;
                *)
                    log_warn "No se pudo determinar cómo leer versión de $file_path"
                    continue
                    ;;
            esac
        fi

        if [[ "$actual_version" != "$expected_version" ]]; then
            log_error "Versión en $file_path ($actual_version) no coincide con la esperada ($expected_version)"
            verification_failed=true
        else
            log_info "✓ $file_path: $actual_version"
        fi
    done

    if $verification_failed; then
        return 1
    fi

    log_success "Todas las versiones verificadas correctamente: ${expected_version}"
    return 0
}

# Rollback all version file changes
rollback_all_version_changes() {
    local version_files_json="$1"
    local rolled_back=false

    local file_count
    file_count=$(echo "$version_files_json" | jq 'length' 2>/dev/null)

    for ((i=0; i<file_count; i++)); do
        local file_path
        file_path=$(echo "$version_files_json" | jq -r ".[$i].path" 2>/dev/null)

        # Make path absolute if relative
        if [[ ! "$file_path" =~ ^/ ]]; then
            file_path="${REPO_ROOT}/${file_path}"
        fi

        if [[ -f "${file_path}.bak" ]]; then
            mv "${file_path}.bak" "$file_path"
            log_info "Rollback completado: $file_path"
            rolled_back=true
        fi
    done

    if $rolled_back; then
        log_success "Rollback de cambios de versión completado"
    else
        log_warn "No se encontraron backups para hacer rollback"
    fi
}
