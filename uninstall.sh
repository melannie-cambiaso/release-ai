#!/usr/bin/env bash
# uninstall.sh - Uninstall release-ai
# Based on gentleman-guardian-angel uninstallation pattern

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Main uninstallation
main() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║   release-ai Uninstallation                ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""

    local found=false

    # Check and remove binary from /usr/local/bin
    if [[ -f "/usr/local/bin/release-ai" ]]; then
        log_info "Eliminando /usr/local/bin/release-ai..."
        rm -f "/usr/local/bin/release-ai"
        log_success "Binario eliminado de /usr/local/bin"
        found=true
    fi

    # Check and remove binary from ~/.local/bin
    if [[ -f "$HOME/.local/bin/release-ai" ]]; then
        log_info "Eliminando $HOME/.local/bin/release-ai..."
        rm -f "$HOME/.local/bin/release-ai"
        log_success "Binario eliminado de ~/.local/bin"
        found=true
    fi

    # Remove share directory
    local share_dir="$HOME/.local/share/release-ai"
    if [[ -d "$share_dir" ]]; then
        log_info "Eliminando $share_dir..."
        rm -rf "$share_dir"
        log_success "Directorio de librerías eliminado"
        found=true
    fi

    # Ask about global config
    local global_config="$HOME/.config/release-ai"
    if [[ -d "$global_config" ]]; then
        echo ""
        read -p "¿Eliminar configuración global ($global_config)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$global_config"
            log_success "Configuración global eliminada"
            found=true
        else
            log_info "Configuración global preservada"
        fi
    fi

    # Check if anything was found
    if [[ "$found" == "false" ]]; then
        log_warn "release-ai no parece estar instalado"
        exit 0
    fi

    echo ""
    log_success "Desinstalación completada"
    echo ""
    log_warn "Nota: Los archivos específicos del proyecto no fueron eliminados:"
    echo "  - .release-ai.config.json (configuración de proyecto)"
    echo "  - .release-state.json (estado de releases)"
    echo ""
    echo "Si deseas eliminarlos, hazlo manualmente en cada proyecto."
    echo ""
}

main "$@"
