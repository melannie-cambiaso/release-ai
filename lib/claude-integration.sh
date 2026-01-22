#!/usr/bin/env bash
# claude-integration.sh - Claude AI integration using direct API calls with curl
# Provides AI-powered features for release automation

# Check if Claude is configured
claude_is_configured() {
    local api_key="${ANTHROPIC_API_KEY:-$(get_config "anthropic_api_key")}"
    [[ -n "$api_key" ]]
}

# Call Claude API using curl
# Args: prompt, max_tokens (optional)
claude_api_call() {
    local prompt="$1"
    local max_tokens="${2:-2048}"

    # Get API key from env or config
    local api_key="${ANTHROPIC_API_KEY:-$(get_config "anthropic_api_key")}"

    if [[ -z "$api_key" ]]; then
        log_error "API key de Claude no configurada"
        log_info "Configura ANTHROPIC_API_KEY o ejecuta 'release-ai init'"
        return 1
    fi

    # Get model from config
    local model=$(get_config "claude.model" "claude-sonnet-4-5-20250929")

    # Escape prompt for JSON (replace newlines and quotes)
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)

    # Make API call with timeout
    local response
    response=$(curl -s --max-time 30 https://api.anthropic.com/v1/messages \
        -H "content-type: application/json" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"$model\",
            \"max_tokens\": $max_tokens,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": $escaped_prompt
            }]
        }"
    )

    local curl_exit=$?
    if [[ $curl_exit -ne 0 ]]; then
        log_error "Error en conexión con Claude API (código: $curl_exit)"
        if [[ $curl_exit -eq 28 ]]; then
            log_error "Timeout: La API no respondió en 30 segundos"
        fi
        return 1
    fi

    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.error.message')
        log_error "Error de Claude API: $error_msg"
        return 1
    fi

    # Extract text from response
    echo "$response" | jq -r '.content[0].text'
}

# Suggest next version based on commits
# Returns: version bump type and suggested version
claude_suggest_version() {
    log_info "Analizando commits con Claude AI..."

    # Get commits since last tag
    local commits
    commits=$(get_commits_since_last_tag)

    if [[ -z "$commits" ]]; then
        log_warn "No hay commits desde el último release"
        return 1
    fi

    log_info "Commits obtenidos: $(echo "$commits" | wc -l) líneas"

    # Get current version (will try package.json first, then fallback to VERSION file)
    local current_version
    current_version=$(get_current_version "$PACKAGE_JSON")

    if [[ -z "$current_version" ]]; then
        log_error "No se pudo obtener la versión actual del archivo de versiones"
        return 1
    fi

    log_info "Versión actual: $current_version"

    # Build prompt
    local prompt="Eres un experto en semantic versioning y conventional commits.

Analiza los siguientes commits y determina el tipo de bump de versión necesario (major, minor, o patch).

Versión actual: $current_version

Commits:
$commits

Instrucciones:
1. Revisa cada commit siguiendo conventional commits (feat:, fix:, BREAKING CHANGE:, etc.)
2. Determina si hay breaking changes (! o BREAKING CHANGE:) → major bump
3. Si hay nuevas features (feat:) → minor bump
4. Si solo hay fixes (fix:) o otros cambios → patch bump
5. Responde SOLO en el siguiente formato JSON:

{
  \"bump_type\": \"major|minor|patch\",
  \"suggested_version\": \"X.Y.Z\",
  \"reasoning\": \"Breve explicación de por qué este tipo de bump\",
  \"highlights\": [\"feature 1\", \"fix 1\", \"breaking change 1\"]
}

Responde ÚNICAMENTE con el JSON, sin markdown ni explicaciones adicionales."

    log_info "Enviando solicitud a Claude API..."

    # Call Claude
    local response
    response=$(claude_api_call "$prompt" 500)

    if [[ $? -ne 0 ]]; then
        log_error "Fallo al llamar a Claude API"
        return 1
    fi

    log_info "Respuesta recibida de Claude API"

    # Parse and display response
    echo "$response"
}

# Generate release notes for a version
# Args: version, output_file (optional), end_ref (optional - default: HEAD)
claude_generate_notes() {
    local version="$1"
    local output_file="${2:-}"
    local end_ref="${3:-HEAD}"

    log_info "Generando release notes para v${version} con Claude AI..."

    # Get commits since last tag
    local commits
    commits=$(get_commits_since_last_tag "$end_ref" 2>&1)

    if [[ -z "$commits" ]]; then
        log_error "No hay commits desde el último release"
        log_error "Esto puede ocurrir si no hay tags previos o si no hay commits nuevos"
        return 1
    fi

    log_info "Commits encontrados: $(echo "$commits" | wc -l) líneas"

    # Build prompt
    local prompt="Eres un experto en documentación de releases y comunicación técnica.

Genera release notes profesionales en español para la versión $version basándote en los siguientes commits:

$commits

Instrucciones:
1. Comienza con una descripción breve (1-2 frases) resumiendo los cambios principales
2. Agrupa los cambios por categorías: Features, Bug Fixes, Breaking Changes, Other Changes
3. Usa formato markdown limpio y profesional (NO incluyas título principal H1, comenzar con la descripción)
4. Cada ítem debe ser claro y conciso
5. Si hay breaking changes, resáltalos con ⚠️
6. Usa emojis apropiados: 🚀 features, 🐛 fixes, 💥 breaking, 📝 docs, etc.

Formato esperado (SIN título H1):

[Descripción breve del release en 1-2 frases]

## 🚀 Features
- Descripción de feature 1
- Descripción de feature 2

## 🐛 Bug Fixes
- Descripción de fix 1
- Descripción de fix 2

## 💥 Breaking Changes
⚠️ **IMPORTANTE**: [Descripción de breaking change]

## 📝 Other Changes
- Otros cambios relevantes

Genera solo el contenido markdown, sin comillas ni delimitadores de código. NO incluyas el título \"# Release v${version}\"."

    # Call Claude
    local notes
    notes=$(claude_api_call "$prompt" 2048)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Save to file if specified
    if [[ -n "$output_file" ]]; then
        echo "$notes" > "$output_file"
        log_success "Release notes guardadas en: $output_file"
    else
        echo "$notes"
    fi
}

# Generate Confluence-formatted release summary
# Args: version, output_file (optional), end_ref (optional - default: HEAD)
# Returns: Confluence wiki markup formatted release notes
claude_generate_confluence_summary() {
    local version="$1"
    local output_file="${2:-}"
    local end_ref="${3:-HEAD}"

    log_info "Generando summary de release para Confluence v${version} con Claude AI..."

    # Get commits since last tag
    local commits
    commits=$(get_commits_since_last_tag "$end_ref" 2>&1)

    if [[ -z "$commits" ]]; then
        log_error "No hay commits desde el último release para Confluence"
        return 1
    fi

    log_info "Commits encontrados para Confluence: $(echo "$commits" | wc -l) líneas"

    # Build prompt for Confluence format
    local prompt="Eres un experto en documentación de releases y comunicación técnica.

Genera un summary de release profesional en FORMATO CONFLUENCE WIKI MARKUP para la versión $version basándote en los siguientes commits:

$commits

Instrucciones:
1. Usa formato de Confluence Wiki Markup (NO markdown)
2. Comienza con un panel info con resumen ejecutivo
3. Agrupa los cambios por categorías con headings h2
4. Usa listas con bullets (-)
5. Usa emojis para categorías: 🚀 features, 🐛 fixes, 💥 breaking, 📝 docs
6. Para breaking changes usa un panel warning
7. Usa formato de código inline con {{monospace}}
8. El resumen debe ser ejecutivo, claro y conciso (2-3 oraciones)

Formato esperado (CONFLUENCE WIKI MARKUP):

{info:title=Release v${version} - Resumen Ejecutivo}
[2-3 oraciones resumiendo los cambios más importantes del release]
{info}

h2. 🚀 Nuevas Funcionalidades
- Descripción clara de feature 1
- Descripción clara de feature 2

h2. 🐛 Correcciones de Bugs
- Descripción del fix 1
- Descripción del fix 2

h2. 💥 Breaking Changes
{warning:title=Cambios que Requieren Acción}
⚠️ *IMPORTANTE*: [Descripción detallada del breaking change y qué acción tomar]
{warning}

h2. 📝 Otros Cambios
- Mejoras de rendimiento
- Actualizaciones de documentación
- Refactorizaciones internas

h2. ℹ️ Información Adicional
*Fecha*: $(date +"%Y-%m-%d")
*Versión*: ${version}
*Ambiente*: [Staging/Production]

Genera solo el contenido en formato Confluence Wiki Markup, sin explicaciones adicionales."

    # Call Claude with higher token limit for detailed summary
    local summary
    summary=$(claude_api_call "$prompt" 2048)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Save to file if specified
    if [[ -n "$output_file" ]]; then
        echo "$summary" > "$output_file"
        log_success "Confluence summary guardado en: $output_file"
    else
        echo "$summary"
    fi
}

# Generate Confluence-formatted release summary in Markdown (Spanish)
# Args: version, output_file (optional), end_ref (optional - default: HEAD)
# Returns: Markdown formatted release notes for Confluence in Spanish
claude_generate_confluence_md() {
    local version="$1"
    local output_file="${2:-}"
    local end_ref="${3:-HEAD}"

    log_info "Generando summary de release en Markdown para Confluence v${version} con Claude AI..."

    # Get commits since last tag
    local commits
    commits=$(get_commits_since_last_tag "$end_ref" 2>&1)

    if [[ -z "$commits" ]]; then
        log_error "No hay commits desde el último release para Confluence Markdown"
        return 1
    fi

    log_info "Commits encontrados para Confluence MD: $(echo "$commits" | wc -l) líneas"

    # Build prompt for Confluence Markdown format
    local prompt="Eres un experto en documentación de releases y comunicación técnica.

Genera un summary de release profesional en FORMATO MARKDOWN EN ESPAÑOL para la versión $version basándote en los siguientes commits:

$commits

Instrucciones:
1. Usa formato Markdown limpio y profesional
2. Comienza con un bloque de resumen ejecutivo destacado
3. Agrupa los cambios por categorías con headings (##)
4. Usa listas con bullets (-)
5. Usa emojis para categorías: 🚀 features, 🐛 fixes, 💥 breaking, 📝 docs, ⚡ performance, 🔧 chores
6. Para breaking changes usa un bloque de advertencia con emoji
7. Usa formato de código inline con backticks cuando sea necesario
8. El resumen debe ser ejecutivo, claro y conciso (2-3 oraciones)
9. TODO en español profesional

Formato esperado (MARKDOWN):

> **📋 Resumen Ejecutivo**
>
> [2-3 oraciones resumiendo los cambios más importantes del release]

## 🚀 Nuevas Funcionalidades

- Descripción clara y concisa de feature 1
- Descripción clara y concisa de feature 2

## 🐛 Correcciones de Bugs

- Descripción del fix 1 con contexto
- Descripción del fix 2 con contexto

## 💥 Breaking Changes

> **⚠️ IMPORTANTE - Cambios que Requieren Acción**
>
> [Descripción detallada del breaking change y qué acción tomar]

## ⚡ Mejoras de Rendimiento

- Optimización 1
- Optimización 2

## 📝 Otros Cambios

- Mejoras de documentación
- Refactorizaciones internas
- Actualizaciones de dependencias

---

**ℹ️ Información del Release**

- **Versión:** ${version}
- **Fecha:** $(date +"%d/%m/%Y")
- **Ambiente:** [Staging/Production]

Genera solo el contenido en formato Markdown en español, sin delimitadores de código ni explicaciones adicionales."

    # Call Claude with higher token limit for detailed summary
    local summary
    summary=$(claude_api_call "$prompt" 2048)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Save to file if specified
    if [[ -n "$output_file" ]]; then
        echo "$summary" > "$output_file"
        log_success "Confluence Markdown summary guardado en: $output_file"
    else
        echo "$summary"
    fi
}

# Validate changes before release
# Returns: list of warnings/issues or "OK"
claude_validate_changes() {
    log_info "Validando cambios con Claude AI..."

    # Get commits since last tag
    local commits
    commits=$(get_commits_since_last_tag)

    if [[ -z "$commits" ]]; then
        log_warn "No hay commits desde el último release"
        return 0
    fi

    # Get git diff
    local diff
    diff=$(git diff HEAD~10..HEAD 2>/dev/null | head -500)

    # Build prompt
    local prompt="Eres un experto en quality assurance y release management.

Analiza los siguientes cambios y detecta posibles problemas antes del release:

Commits:
$commits

Diff (últimas 500 líneas):
$diff

Revisa:
1. ¿Hay breaking changes sin documentar con BREAKING CHANGE?
2. ¿Los commits siguen conventional commits?
3. ¿Hay cambios en código sin tests asociados? (archivos .test. o .spec.)
4. ¿Hay TODOs o FIXMEs en el código?
5. ¿Hay console.log, debugger, o código de depuración?
6. ¿La versión en package.json es consistente?

Responde en el siguiente formato:

ESTADO: [OK | WARNINGS | ERRORS]

[Si hay warnings o errors, lista cada uno con -]

Ejemplo:
ESTADO: WARNINGS
- Breaking change en función X sin documentar con BREAKING CHANGE:
- Se modificó componente Y sin tests asociados
- Hay 2 console.log en archivo Z

Si todo está bien, solo responde:
ESTADO: OK
✓ Todos los checks pasaron correctamente"

    # Call Claude
    local validation
    validation=$(claude_api_call "$prompt" 1024)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo "$validation"
}

# Interactive conversational assistant for releases
# Args: message (optional for first prompt)
claude_assist() {
    local initial_message="${1:-}"

    log_phase "Asistente Claude para Releases"
    log_info "Escribe 'exit' o 'quit' para salir"
    echo ""

    # If no initial message, start conversation
    if [[ -z "$initial_message" ]]; then
        echo "¿En qué puedo ayudarte con tu release?"
        echo ""
    fi

    # Conversation loop
    while true; do
        # Read user input
        if [[ -n "$initial_message" ]]; then
            local user_input="$initial_message"
            initial_message=""  # Clear after first use
        else
            read -p "Tú: " -r user_input
        fi

        # Check for exit
        if [[ "$user_input" == "exit" ]] || [[ "$user_input" == "quit" ]]; then
            log_info "Saliendo del asistente..."
            break
        fi

        # Skip empty input
        if [[ -z "$user_input" ]]; then
            continue
        fi

        # Build context-aware prompt
        local prompt="Eres un asistente experto en release management y git workflows.

El usuario está trabajando en un release y necesita ayuda.

Usuario pregunta: $user_input

Repositorio actual:
- Directorio: $(pwd)
- Branch actual: $(git_current_branch 2>/dev/null || echo "unknown")
- Último commit: $(git log -1 --oneline 2>/dev/null || echo "unknown")

Proporciona una respuesta útil, concisa y accionable. Si es necesario ejecutar comandos, indícalos claramente."

        # Call Claude
        echo ""
        echo "Claude:"
        local response
        response=$(claude_api_call "$prompt" 1024)

        if [[ $? -eq 0 ]]; then
            echo "$response"
        else
            log_error "Error al comunicarse con Claude"
        fi
        echo ""
    done
}

# Export functions
export -f claude_is_configured
export -f claude_api_call
export -f claude_suggest_version
export -f claude_generate_notes
export -f claude_generate_confluence_summary
export -f claude_generate_confluence_md
export -f claude_validate_changes
export -f claude_assist
