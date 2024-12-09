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

    # Create LSP directory in user's home
    log "INFO" "Creating LSP directory..."
    mkdir -p ~/lsp || exit_on_error "Failed to create LSP directory"

    # Remove existing ElixirLS repositories if they exist
    if [ -d ~/lsp/elixir-ls ]; then
        log "WARN" "Existing ElixirLS repository found in ~/lsp/elixir-ls. Removing..."
        rm -rf ~/lsp/elixir-ls || exit_on_error "Failed to remove existing ElixirLS repository in ~/lsp"
    fi

    if [ -d /usr/local/elixir-ls ]; then
        log "WARN" "Existing ElixirLS installation found in /usr/local/elixir-ls. Removing..."
        rm -rf /usr/local/elixir-ls || exit_on_error "Failed to remove existing ElixirLS installation in /usr/local"
    fi

    # Create installation directories
    log "INFO" "Creating necessary directories..."
    mkdir -p /usr/local/elixir-ls || exit_on_error "Failed to create installation directories"

    # Install Erlang and Elixir
    log "INFO" "Installing Erlang and Elixir..."
    dnf install -y erlang elixir || exit_on_error "Failed to install Erlang and Elixir"

    # Verify mix is now available
    if ! command -v mix &> /dev/null; then
        exit_on_error "mix command not found after installation"
    fi

    # Clone ElixirLS repository
    log "INFO" "Cloning ElixirLS repository..."
    git clone https://github.com/elixir-lsp/elixir-ls.git ~/lsp/elixir-ls || exit_on_error "Failed to clone ElixirLS repository"

    # Build ElixirLS
    cd ~/lsp/elixir-ls || exit_on_error "Failed to change to source directory"
    log "INFO" "Fetching dependencies..."
    mix deps.get || exit_on_error "Failed to fetch dependencies"

    log "INFO" "Compiling ElixirLS..."
    MIX_ENV=prod mix compile || exit_on_error "Compilation failed"

    # Create release
    log "INFO" "Creating ElixirLS release..."
    MIX_ENV=prod mix elixir_ls.release2 -o /usr/local/elixir-ls || exit_on_error "Failed to create release"

    # Setup language server
    log "INFO" "Setting up language server..."
    cd /usr/local/elixir-ls || exit_on_error "Failed to change to release directory"

    # Search for language_server.sh, make it executable, rename, and create a symbolic link
    find . -type f -name "language_server.sh" | while read -r file; do
        dir=$(dirname "$file")
        mv "$file" "$dir/elixir-ls" || { log "ERROR" "Failed to rename $file to elixir-ls"; exit 1; }
        chmod +x "$dir/elixir-ls" || { log "ERROR" "Failed to make $dir/elixir-ls executable"; exit 1; }
        ln -sf "$PWD/$dir/elixir-ls" /usr/local/bin/elixir-ls || { log "ERROR" "Failed to create symbolic link"; exit 1; }
        log "INFO" "Symbolic link created for $dir/elixir-ls at /usr/local/bin/elixir-ls"
        break  # Exit after handling the first match
    done

    if [ $? -ne 0 ]; then
        log "ERROR" "No file named 'language_server.sh' found or failed to process."
        exit 1
    fi

    # Update PATH (use .profile for wider compatibility)
    log "INFO" "Updating PATH environment variable..."
    {
        echo '# ElixirLS PATH additions'
        echo 'export PATH="$PATH:/usr/bin/mix"'
        echo 'export PATH="$PATH:/usr/bin/elixir"'
        echo 'export PATH="$PATH:/usr/local/bin/elixir-ls"'
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

log "INFO" "Installation completed. Please restart your terminal."
