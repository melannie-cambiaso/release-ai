#!/bin/bash
# logging.sh - Logging and progress utilities for release automation
# Provides colored logging, progress indicators, and state management

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# State file location (configurable via environment variable or defaults to current directory)
STATE_FILE="${STATE_FILE:-$(pwd)/.release-state.json}"

# Configuration loading
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    # Read configuration values using jq
    # Returns empty string if key doesn't exist
    jq -r ".$2 // empty" "$config_file" 2>/dev/null
}

# Get configuration value with fallback hierarchy:
# 1. Environment variable
# 2. Project config (.release-ai.config.json)
# 3. Global config (~/.config/release-ai/config.json)
# 4. Default value
get_config() {
    local key="$1"
    local default="${2:-}"

    # Convert snake_case to SCREAMING_SNAKE_CASE for env var
    local env_var=$(echo "$key" | tr '[:lower:]' '[:upper:]')

    # Check environment variable first
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    # Check project config
    if [[ -f ".release-ai.config.json" ]]; then
        local value=$(load_config ".release-ai.config.json" "$key")
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi

    # Check global config
    if [[ -f "$HOME/.config/release-ai/config.json" ]]; then
        local value=$(load_config "$HOME/.config/release-ai/config.json" "$key")
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi

    # Return default
    echo "$default"
}

# Get version_files array from config as JSON
get_version_files_config() {
    local config_file

    # Check project config first
    if [[ -f ".release-ai.config.json" ]]; then
        config_file=".release-ai.config.json"
    # Check global config
    elif [[ -f "$HOME/.config/release-ai/config.json" ]]; then
        config_file="$HOME/.config/release-ai/config.json"
    else
        echo "[]"
        return 1
    fi

    # Extract version_files array
    jq -c '.version_files // []' "$config_file" 2>/dev/null || echo "[]"
}

# Log levels
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_phase() {
    echo ""
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}  $*${NC}"
    echo -e "${PURPLE}========================================${NC}"
    echo ""
}

log_step() {
    local step_num="$1"
    shift
    echo -e "${GREEN}[Step ${step_num}]${NC} $*"
}

# State management functions
save_state() {
    local key="$1"
    local value="$2"

    # Create empty state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "{}" > "$STATE_FILE"
    fi

    # Update state using jq
    local temp_file
    temp_file=$(mktemp)
    if jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$STATE_FILE"
    else
        log_error "Failed to save state: $key=$value"
        rm -f "$temp_file"
        return 1
    fi
}

get_state() {
    local key="$1"

    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return 1
    fi

    local value
    value=$(jq -r --arg k "$key" '.[$k] // ""' "$STATE_FILE" 2>/dev/null)
    echo "$value"
}

clear_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_info "Estado limpiado"
    fi
}

# Pause for keypass input
pause_for_keypass() {
    local message="$1"
    echo ""
    echo -e "${YELLOW}⏸️  ${message}${NC}"
    echo "Presiona ENTER cuando estés listo (después de ingresar keypass si es necesario)..."
    read -r
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required tools
validate_required_tools() {
    local missing_tools=()

    if ! command_exists jq; then
        missing_tools+=("jq")
    fi

    if ! command_exists git; then
        missing_tools+=("git")
    fi

    if ! command_exists gh; then
        missing_tools+=("gh")
    fi

    if ! command_exists curl; then
        missing_tools+=("curl")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Herramientas faltantes: ${missing_tools[*]}"
        log_error "Por favor instala las herramientas necesarias antes de continuar"
        return 1
    fi

    return 0
}
