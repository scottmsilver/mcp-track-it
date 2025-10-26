#!/bin/bash
# MCP Process Wrapper - Installation with scope options

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_CMD="/home/ssilver/anaconda3/bin/python3"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}MCP Process Wrapper - Installer${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check if Claude is running
check_claude_running() {
    pgrep -f "claude" > /dev/null 2>&1
}

# Kill Claude processes
kill_claude() {
    echo -e "${YELLOW}Stopping Claude processes...${NC}"
    pkill -f claude 2>/dev/null || true
    sleep 2

    if check_claude_running; then
        echo -e "${YELLOW}Force killing remaining Claude processes...${NC}"
        pkill -9 -f claude 2>/dev/null || true
        sleep 1
    fi

    if check_claude_running; then
        echo -e "${RED}✗ Failed to stop all Claude processes${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Claude processes stopped${NC}"
        return 0
    fi
}

# Remove existing installations
cleanup_existing() {
    echo -e "${YELLOW}Cleaning up existing installations...${NC}"

    # Remove from local config
    claude mcp remove process-wrapper -s local 2>/dev/null || true

    # Remove from global config
    claude mcp remove process-wrapper 2>/dev/null || true

    # Clean ~/.claude/mcp.json if it exists
    if [ -f "$HOME/.claude/mcp.json" ]; then
        if grep -q "process-wrapper" "$HOME/.claude/mcp.json" 2>/dev/null; then
            echo "  Backing up global mcp.json..."
            cp "$HOME/.claude/mcp.json" "$HOME/.claude/mcp.json.backup.$(date +%Y%m%d_%H%M%S)"

            # Remove process-wrapper entry
            python3 -c "
import json
with open('$HOME/.claude/mcp.json', 'r') as f:
    config = json.load(f)
if 'mcpServers' in config and 'process-wrapper' in config['mcpServers']:
    del config['mcpServers']['process-wrapper']
    with open('$HOME/.claude/mcp.json', 'w') as f:
        json.dump(config, f, indent=2)
" 2>/dev/null || true
        fi
    fi

    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Install globally (available in all projects)
install_global() {
    echo -e "${BLUE}Installing GLOBALLY (available in all projects)${NC}"
    echo ""

    # Create ~/.claude directory if needed
    mkdir -p "$HOME/.claude"

    # Create or update mcp.json
    cat > "$HOME/.claude/mcp.json" << EOF
{
  "mcpServers": {
    "process-wrapper": {
      "command": "$PYTHON_CMD",
      "args": ["$SCRIPT_DIR/mcp_server.py"],
      "env": {
        "MCP_PROCESS_WRAPPER_LOG_DIR": "$SCRIPT_DIR/process_logs",
        "MCP_PROCESS_REGISTRY_DB": "$SCRIPT_DIR/process_registry.db"
      }
    }
  }
}
EOF

    echo -e "${GREEN}✓ Global configuration created${NC}"
    echo "  Config file: $HOME/.claude/mcp.json"
    echo ""
    echo -e "${YELLOW}⚠ Claude must be restarted to load global MCP servers${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start Claude: claude"
    echo "  2. Test with: list_processes()"

    return 0
}

# Install locally (current project only)
install_local() {
    echo -e "${BLUE}Installing LOCALLY (current project only)${NC}"
    echo ""

    # Use Claude CLI to add
    if claude mcp add --transport stdio process-wrapper \
        --env MCP_PROCESS_WRAPPER_LOG_DIR="$SCRIPT_DIR/process_logs" \
        --env MCP_PROCESS_REGISTRY_DB="$SCRIPT_DIR/process_registry.db" \
        -- "$PYTHON_CMD" "$SCRIPT_DIR/mcp_server.py" 2>&1 | grep -q "Added"; then

        echo -e "${GREEN}✓ Local installation successful${NC}"
        echo "  Scope: Current project only"
        echo "  No restart needed - available immediately"
    else
        echo -e "${RED}✗ Local installation failed${NC}"
        return 1
    fi

    return 0
}

# Main installation flow
echo -e "${YELLOW}Step 1: Choose installation scope...${NC}"
echo ""
echo -e "${BLUE}Installation Options:${NC}"
echo ""
echo "1) ${GREEN}LOCAL${NC} (Recommended)"
echo "   - Only available in this project"
echo "   - ${GREEN}No restart needed, Claude can be running${NC}"
echo "   - Dynamically loaded"
echo "   - Best for project-specific tools"
echo ""
echo "2) ${GREEN}GLOBAL${NC}"
echo "   - Available in ALL projects"
echo "   - ${YELLOW}Requires Claude restart${NC}"
echo "   - Always loaded at startup"
echo "   - Best for tools you use everywhere"
echo ""
read -p "Choose installation type [1-2]: " -n 1 -r
echo ""
echo ""

# Step 2: Check if we need to handle Claude being running
NEED_CLAUDE_STOPPED=false
case $REPLY in
    1)
        # LOCAL - Claude can be running!
        echo -e "${GREEN}Local installation selected - Claude can stay running${NC}"
        INSTALL_TYPE="local"
        ;;
    2)
        # GLOBAL - Need to check/stop Claude
        echo -e "${YELLOW}Global installation selected - checking Claude status${NC}"
        INSTALL_TYPE="global"
        NEED_CLAUDE_STOPPED=true
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Only check/stop Claude if doing GLOBAL install
if [ "$NEED_CLAUDE_STOPPED" = true ]; then
    echo ""
    echo -e "${YELLOW}Step 2: Checking Claude status for global install...${NC}"

    if check_claude_running; then
        echo -e "${YELLOW}⚠ Claude is running and must be stopped for global installation${NC}"
        echo ""
        echo "Options:"
        echo "  1) Stop Claude and continue"
        echo "  2) Cancel installation"
        echo ""
        read -p "Choose [1-2]: " -n 1 -r
        echo ""

        if [[ $REPLY == "1" ]]; then
            if ! kill_claude; then
                echo -e "${RED}Failed to stop Claude. Please close it manually and try again.${NC}"
                exit 1
            fi
        else
            echo "Installation cancelled"
            exit 0
        fi
    else
        echo -e "${GREEN}✓ Claude is not running${NC}"
    fi
fi

# Step 3: Clean up and install
echo ""
echo -e "${YELLOW}Step 3: Removing existing installations...${NC}"
cleanup_existing

echo ""
echo -e "${YELLOW}Step 4: Installing MCP server...${NC}"

case $INSTALL_TYPE in
    "local")
        install_local
        ;;
    "global")
        install_global
        ;;
esac

# Create test process
echo ""
echo -e "${YELLOW}Step 5: Creating test process...${NC}"

TEST_ID="install-test-$(date +%s)"
"$SCRIPT_DIR/track-it" --id "$TEST_ID" bash -c "echo 'Test output'; echo 'Test error' >&2" >/dev/null 2>&1

if [ -f "$SCRIPT_DIR/process_logs/$TEST_ID.log" ]; then
    echo -e "${GREEN}✓ Test process created: $TEST_ID${NC}"
else
    echo -e "${YELLOW}⚠ Test process creation failed${NC}"
fi

# Final summary
echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Installation Complete!${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

if [ "$INSTALL_TYPE" == "local" ]; then
    echo -e "${GREEN}✅ LOCAL installation successful${NC}"
    echo ""
    echo "The MCP server is available in this project."
    echo "You can immediately use it in Claude:"
    echo "  list_processes()"
    echo ""
    echo "Note: Only works when Claude is run from:"
    echo "  $SCRIPT_DIR"
else
    echo -e "${GREEN}✅ GLOBAL installation successful${NC}"
    echo ""
    echo "The MCP server will be available in ALL projects."
    echo ""
    echo -e "${YELLOW}⚠ You must restart Claude to load the MCP server${NC}"
    echo ""
    echo "Steps:"
    echo "  1. Run: claude"
    echo "  2. Test: list_processes()"
fi

echo ""
echo "To track processes from anywhere:"
echo "  $SCRIPT_DIR/track-it <command>"
echo ""
echo "Or add to PATH:"
echo "  export PATH=\"\$PATH:$SCRIPT_DIR\""
echo ""
echo "Test process ID: $TEST_ID"
