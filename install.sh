#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKELETON_SH="$SCRIPT_DIR/skeleton.sh"
INSTALL_DIR="$HOME/.local/bin"
LINK_PATH="$INSTALL_DIR/skeleton"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

uninstall() {
    if [[ -L "$LINK_PATH" ]]; then
        rm "$LINK_PATH"
        echo -e "${GREEN}Removed symlink: $LINK_PATH${NC}"
    elif [[ -e "$LINK_PATH" ]]; then
        echo -e "${RED}$LINK_PATH exists but is not a symlink. Please remove it manually.${NC}"
        exit 1
    else
        echo -e "${YELLOW}Nothing to remove — $LINK_PATH does not exist.${NC}"
    fi
    exit 0
}

install() {
    # Verify skeleton.sh exists
    if [[ ! -f "$SKELETON_SH" ]]; then
        echo -e "${RED}Error: skeleton.sh not found in $SCRIPT_DIR${NC}"
        exit 1
    fi

    # Make sure skeleton.sh is executable
    chmod +x "$SKELETON_SH"

    # Create ~/.local/bin if it doesn't exist
    mkdir -p "$INSTALL_DIR"

    # Create or update the symlink
    if [[ -L "$LINK_PATH" ]]; then
        rm "$LINK_PATH"
        echo -e "${YELLOW}Updating existing symlink...${NC}"
    elif [[ -e "$LINK_PATH" ]]; then
        echo -e "${RED}$LINK_PATH already exists and is not a symlink. Please remove it manually.${NC}"
        exit 1
    fi

    ln -s "$SKELETON_SH" "$LINK_PATH"
    echo -e "${GREEN}Installed: $LINK_PATH → $SKELETON_SH${NC}"

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        echo -e "${YELLOW}~/.local/bin is not in your PATH.${NC}"
        echo "Add this line to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo -e "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        echo "Then restart your terminal or run: source ~/.bashrc"
    else
        echo ""
        echo -e "You can now run ${GREEN}skeleton${NC} from anywhere."
    fi
}

case "${1:-}" in
    --uninstall)
        uninstall
        ;;
    --help|-h)
        echo "Usage: ./install.sh [OPTIONS]"
        echo ""
        echo "  (no args)     Install skeleton to ~/.local/bin"
        echo "  --uninstall   Remove the skeleton symlink"
        echo "  --help        Show this message"
        ;;
    *)
        install
        ;;
esac
