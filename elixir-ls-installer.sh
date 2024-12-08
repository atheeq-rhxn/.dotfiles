#!/bin/bash

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    local message=$2
    local color=$NC

    case $level in
        "INFO")
            color=$GREEN
            ;;
        "WARN")
            color=$YELLOW
            ;;
        "ERROR")
            color=$RED
            ;;
    esac

    echo -e "${color}[$level]${NC} $message"
}

# Error handling function
exit_on_error() {
    local message=$1
    log "ERROR" "$message"
    exit 1
}

# Privilege check
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "This script must be run with root privileges (use sudo)"
    exit 1
fi

# Dependency check
check_dependencies() {
    local dependencies=("git" "dnf")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            exit_on_error "Dependency '$dep' is not installed"
        fi
    done
}

# Main installation process
main() {
    # Check dependencies
    check_dependencies

    # Create installation directories
    log "INFO" "Creating necessary directories..."
    mkdir -p ~/lsp /usr/local/elixir-ls || exit_on_error "Failed to create directories"

    # Install Erlang and Elixir
    log "INFO" "Installing Erlang and Elixir..."
    dnf install -y erlang elixir || exit_on_error "Failed to install Erlang and Elixir"

    # Verify mix is now available
    if ! command -v mix &> /dev/null; then
        exit_on_error "mix command not found after installation"
    fi

    # Clone ElixirLS repository
    log "INFO" "Cloning ElixirLS repository..."
    cd ~/lsp || exit_on_error "Failed to change directory"
    git clone https://github.com/elixir-lsp/elixir-ls || exit_on_error "Failed to clone ElixirLS repository"

    # Build ElixirLS
    cd elixir-ls || exit_on_error "Failed to change to elixir-ls directory"
    log "INFO" "Fetching dependencies..."
    mix deps.get || exit_on_error "Failed to fetch dependencies"

    log "INFO" "Compiling ElixirLS..."
    MIX_ENV=prod mix compile || exit_on_error "Compilation failed"

    # Create release
    log "INFO" "Creating ElixirLS release..."
    MIX_ENV=prod mix elixir_ls.release2 -o /usr/local/elixir-ls || exit_on_error "Failed to create release"

    # Setup language server
    log "INFO" "Setting up language server..."
    cd /usr/local/elixir-ls || exit_on_error "Failed to change to elixir-ls directory"

    # Find and make the language server executable
    find . -type f -executable | grep -E 'language_server|elixir-ls' | while read -r exe; do
        chmod +x "$exe"
        ln -sf "$exe" /usr/local/bin/elixir-ls || exit_on_error "Failed to create symbolic link"
        break  # Use the first matching executable
    done || exit_on_error "No executable found for ElixirLS"

    # Update PATH (use .profile for wider compatibility)
    log "INFO" "Updating PATH environment variable..."
    {
        echo '# ElixirLS PATH additions'
        echo 'export PATH="$PATH:/usr/bin/mix"'
        echo 'export PATH="$PATH:/usr/bin/elixir"'
        echo 'export PATH="$PATH:/usr/local/elixir-ls"'
    } >> ~/.profile

    # Verification
    log "INFO" "Verifying installation..."
    if command -v elixir-ls &> /dev/null; then
        log "INFO" "ElixirLS installed successfully!"
    else
        exit_on_error "ElixirLS installation verification failed"
    fi
}

# Run the main installation process
main

log "INFO" "Installation completed. Please restart your terminal or run 'source ~/.profile'."
