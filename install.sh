#!/usr/bin/env bash
# install.sh - Install release-ai globally
# Based on gentleman-guardian-angel installation pattern

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validando prerequisitos..."

    local missing_tools=()

    if ! command_exists git; then
        missing_tools+=("git")
    fi

    if ! command_exists gh; then
        missing_tools+=("gh")
    fi

    if ! command_exists jq; then
        missing_tools+=("jq")
    fi

    if ! command_exists curl; then
        missing_tools+=("curl")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Herramientas faltantes: ${missing_tools[*]}"
        echo ""
        log_info "Instala las herramientas necesarias:"

        local os=$(detect_os)
        if [[ "$os" == "macos" ]]; then
            echo "  brew install git gh jq"
        else
            echo "  sudo apt-get install git jq curl"
            echo "  # Para gh (GitHub CLI), visita: https://cli.github.com/manual/installation"
        fi

        return 1
    fi

    log_success "Todos los prerequisitos están instalados"
    return 0
}

# Determine installation directory
determine_install_dir() {
    # Try /usr/local/bin first
    if [[ -w "/usr/local/bin" ]]; then
        echo "/usr/local/bin"
        return 0
    fi

    # Try ~/.local/bin as fallback
    local local_bin="$HOME/.local/bin"
    if [[ ! -d "$local_bin" ]]; then
        mkdir -p "$local_bin"
    fi

    if [[ -w "$local_bin" ]]; then
        echo "$local_bin"
        return 0
    fi

    log_error "No se encontró un directorio de instalación escribible"
    log_info "Intenta ejecutar: sudo chown -R $(whoami) /usr/local/bin"
    return 1
}

# Main installation
main() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║   release-ai Installation                  ║"
    echo "║   Automated Release Management with AI     ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""

    # Validate prerequisites
    if ! validate_prerequisites; then
        exit 1
    fi

    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Check if already installed
    if command_exists release-ai; then
        log_warn "release-ai ya está instalado"
        echo ""
        read -p "¿Deseas reinstalar? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Instalación cancelada"
            exit 0
        fi
    fi

    # Determine installation directory
    log_info "Determinando directorio de instalación..."
    INSTALL_DIR=$(determine_install_dir)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    log_success "Directorio de instalación: $INSTALL_DIR"

    # Create share directories
    SHARE_DIR="$HOME/.local/share/release-ai"
    log_info "Creando directorios en $SHARE_DIR..."
    mkdir -p "$SHARE_DIR/lib"
    mkdir -p "$SHARE_DIR/templates"

    # Copy files
    log_info "Copiando archivos..."

    # Copy main binary
    cp "$SCRIPT_DIR/bin/release-ai" "$INSTALL_DIR/release-ai"
    chmod +x "$INSTALL_DIR/release-ai"
    log_success "Binario copiado: $INSTALL_DIR/release-ai"

    # Copy libraries
    cp "$SCRIPT_DIR/lib/"*.sh "$SHARE_DIR/lib/"
    log_success "Librerías copiadas: $SHARE_DIR/lib/"

    # Copy templates
    cp "$SCRIPT_DIR/templates/"* "$SHARE_DIR/templates/" 2>/dev/null || true
    log_success "Templates copiadas: $SHARE_DIR/templates/"

    # Copy example config to share dir
    if [[ -f "$SCRIPT_DIR/.release-ai.config.example.json" ]]; then
        cp "$SCRIPT_DIR/.release-ai.config.example.json" "$SHARE_DIR/"
    fi

    # Update paths in installed binary using sed
    log_info "Actualizando paths en el binario..."
    local os=$(detect_os)

    if [[ "$os" == "macos" ]]; then
        # macOS uses BSD sed
        sed -i '' "s|^LIB_DIR=.*|LIB_DIR=\"\${RELEASE_AI_LIB_DIR:-$SHARE_DIR/lib}\"|" "$INSTALL_DIR/release-ai"
        sed -i '' "s|^TEMPLATES_DIR=.*|TEMPLATES_DIR=\"\${RELEASE_AI_TEMPLATES_DIR:-$SHARE_DIR/templates}\"|" "$INSTALL_DIR/release-ai"
        # Update example config path in cmd_init
        sed -i '' "s|\${SCRIPT_DIR}/../.release-ai.config.example.json|$SHARE_DIR/.release-ai.config.example.json|g" "$INSTALL_DIR/release-ai"
    else
        # Linux uses GNU sed
        sed -i "s|^LIB_DIR=.*|LIB_DIR=\"\${RELEASE_AI_LIB_DIR:-$SHARE_DIR/lib}\"|" "$INSTALL_DIR/release-ai"
        sed -i "s|^TEMPLATES_DIR=.*|TEMPLATES_DIR=\"\${RELEASE_AI_TEMPLATES_DIR:-$SHARE_DIR/templates}\"|" "$INSTALL_DIR/release-ai"
        # Update example config path in cmd_init
        sed -i "s|\${SCRIPT_DIR}/../.release-ai.config.example.json|$SHARE_DIR/.release-ai.config.example.json|g" "$INSTALL_DIR/release-ai"
    fi
    log_success "Paths actualizados"

    # Verify PATH
    log_info "Verificando PATH..."
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        log_warn "$INSTALL_DIR no está en tu PATH"
        echo ""
        log_info "Agrega la siguiente línea a tu ~/.bashrc, ~/.zshrc, o ~/.profile:"
        echo ""
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
    fi

    echo ""
    log_success "¡Instalación completada exitosamente!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📦 release-ai está instalado en: $INSTALL_DIR/release-ai"
    echo "📚 Librerías en: $SHARE_DIR/lib/"
    echo "📝 Templates en: $SHARE_DIR/templates/"
    echo ""
    echo "🚀 Próximos pasos:"
    echo ""
    echo "  1. Verifica la instalación:"
    echo "     $ release-ai version"
    echo ""
    echo "  2. Inicializa en tu proyecto:"
    echo "     $ cd tu-proyecto"
    echo "     $ release-ai init"
    echo ""
    echo "  3. Configura tu API key de Claude (opcional):"
    echo "     Edita ~/.config/release-ai/config.json"
    echo ""
    echo "  4. Crea tu primer release:"
    echo "     $ release-ai start 1.0.0"
    echo ""
    echo "  5. O usa IA para sugerencias:"
    echo "     $ release-ai suggest"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📖 Documentación: https://github.com/your-username/release-ai"
    echo "🐛 Issues: https://github.com/your-username/release-ai/issues"
    echo ""
}

main "$@"
