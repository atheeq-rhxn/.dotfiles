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
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
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
    local dependencies=("$@")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            exit_on_error "Dependency '$dep' is not installed"
        fi
    done
}

# Main installation process
main() {
    # Set installation directory to ~/lsp
    local install_dir="$HOME/lsp"
    local repo_url="https://github.com/elixir-lsp/elixir-ls"
    local dependencies=("git" "dnf")

    log "INFO" "Installation directory set to: $install_dir"
    log "INFO" "Repository URL set to: $repo_url"

    # Check dependencies
    check_dependencies "${dependencies[@]}"

    # Create installation directories
    log "INFO" "Creating necessary directories..."
    mkdir -p "$install_dir" /usr/local/elixir-ls || exit_on_error "Failed to create directories"

    # Install Erlang and Elixir
    log "INFO" "Installing Erlang and Elixir..."
    dnf install -y erlang elixir || exit_on_error "Failed to install Erlang and Elixir"

    # Verify mix is now available
    if ! command -v mix &> /dev/null; then
        exit_on_error "mix command not found after installation"
    fi

    # Remove existing elixir-ls directory if it exists
    if [ -d "$install_dir/elixir-ls" ]; then
        log "WARN" "Existing elixir-ls directory found. Removing it..."
        rm -rf "$install_dir/elixir-ls" || exit_on_error "Failed to remove existing elixir-ls directory"
    fi

    # Clone ElixirLS repository
    log "INFO" "Cloning ElixirLS repository..."
    cd "$install_dir" || exit_on_error "Failed to change directory"
    git clone "$repo_url" || exit_on_error "Failed to clone ElixirLS repository"

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

    # Ensure language_server.sh is executable and linked
    if [ -f "./language_server.sh" ]; then
        chmod +x "./language_server.sh" || exit_on_error "Failed to make language_server.sh executable"
        ln -sf "$(pwd)/language_server.sh" /usr/local/bin/elixir-ls || exit_on_error "Failed to create symbolic link for language_server.sh as elixir-ls"
        log "INFO" "language_server.sh is set up as elixir-ls in /usr/local/bin"
    else
        exit_on_error "language_server.sh not found in /usr/local/elixir-ls"
    fi

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
