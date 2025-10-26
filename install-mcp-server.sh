#!/bin/bash
# Smart install script for MCP Process Wrapper
# Handles both fresh installs and reinstalls/updates

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_CMD="/home/ssilver/anaconda3/bin/python3"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MCP Process Wrapper - Smart Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if MCP server is installed
check_mcp_installed() {
    claude mcp list 2>/dev/null | grep -q "process-wrapper" && return 0 || return 1
}

# Function to check if MCP server is connected
check_mcp_connected() {
    claude mcp list 2>/dev/null | grep "process-wrapper" | grep -q "✓ Connected" && return 0 || return 1
}

# Function to remove existing MCP server
remove_existing_mcp() {
    echo -e "${YELLOW}Removing existing MCP server configuration...${NC}"

    # Try to remove from Claude MCP
    if claude mcp remove process-wrapper -s local 2>/dev/null; then
        echo -e "${GREEN}✓ Removed from local project config${NC}"
    fi

    if claude mcp remove process-wrapper 2>/dev/null; then
        echo -e "${GREEN}✓ Removed from global config${NC}"
    fi

    # Clean up any stale configuration files
    if [ -f "$HOME/.claude/mcp.json" ]; then
        if grep -q "process-wrapper" "$HOME/.claude/mcp.json"; then
            echo -e "${YELLOW}  Backing up old mcp.json...${NC}"
            cp "$HOME/.claude/mcp.json" "$HOME/.claude/mcp.json.backup.$(date +%Y%m%d_%H%M%S)"
            # Remove process-wrapper entry from mcp.json
            python3 -c "
import json
try:
    with open('$HOME/.claude/mcp.json', 'r') as f:
        config = json.load(f)
    if 'mcpServers' in config and 'process-wrapper' in config['mcpServers']:
        del config['mcpServers']['process-wrapper']
        with open('$HOME/.claude/mcp.json', 'w') as f:
            json.dump(config, f, indent=2)
        print('  Cleaned mcp.json')
except: pass
" 2>/dev/null || true
        fi
    fi

    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Step 1: Check for existing installation
echo -e "${YELLOW}Step 1: Checking for existing installation...${NC}"

if check_mcp_installed; then
    echo -e "${YELLOW}⚠ Found existing process-wrapper MCP server${NC}"

    if check_mcp_connected; then
        echo -e "${GREEN}  Status: Connected${NC}"
    else
        echo -e "${RED}  Status: Not connected${NC}"
    fi

    echo -e "${YELLOW}  This will be removed and reinstalled${NC}"

    # Remove existing installation
    remove_existing_mcp

    # Verify removal
    if check_mcp_installed; then
        echo -e "${RED}✗ Failed to remove existing installation${NC}"
        echo "  Please manually run: claude mcp remove process-wrapper"
        exit 1
    else
        echo -e "${GREEN}✓ Existing installation removed successfully${NC}"
    fi
else
    echo -e "${GREEN}✓ No existing installation found (fresh install)${NC}"
fi

# Step 2: Check prerequisites
echo ""
echo -e "${YELLOW}Step 2: Checking prerequisites...${NC}"

# Check Python
if [ ! -f "$PYTHON_CMD" ]; then
    echo -e "${RED}✗ Python not found at: $PYTHON_CMD${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Python found: $($PYTHON_CMD --version)${NC}"
fi

# Check MCP package
if ! $PYTHON_CMD -c "import mcp" 2>/dev/null; then
    echo -e "${RED}✗ MCP package not installed${NC}"
    echo "  Install with: pip install mcp"
    exit 1
else
    echo -e "${GREEN}✓ MCP package installed${NC}"
fi

# Check Claude CLI
if ! command -v claude &> /dev/null; then
    echo -e "${RED}✗ Claude CLI not found${NC}"
    echo "  Please install Claude Code"
    exit 1
else
    echo -e "${GREEN}✓ Claude CLI found: $(which claude)${NC}"
fi

# Check required files
for file in track-it mcp_server.py process_registry.py; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo -e "${RED}✗ Missing required file: $file${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ All required files present${NC}"

# Step 3: Set up directories
echo ""
echo -e "${YELLOW}Step 3: Setting up directories...${NC}"

LOG_DIR="$SCRIPT_DIR/process_logs"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    echo -e "${GREEN}✓ Created log directory: $LOG_DIR${NC}"
else
    echo -e "${GREEN}✓ Log directory exists: $LOG_DIR${NC}"
fi

# Step 4: Install MCP server
echo ""
echo -e "${YELLOW}Step 4: Installing MCP server...${NC}"

# Add the MCP server using Claude CLI
if claude mcp add --transport stdio process-wrapper \
    --env MCP_PROCESS_WRAPPER_LOG_DIR="$LOG_DIR" \
    --env MCP_PROCESS_REGISTRY_DB="$SCRIPT_DIR/process_registry.db" \
    -- "$PYTHON_CMD" "$SCRIPT_DIR/mcp_server.py" 2>&1 | tee /tmp/mcp_add.log | grep -q "Added"; then

    echo -e "${GREEN}✓ MCP server added successfully${NC}"
else
    echo -e "${RED}✗ Failed to add MCP server${NC}"
    echo "  Check /tmp/mcp_add.log for details"
    exit 1
fi

# Step 5: Verify installation
echo ""
echo -e "${YELLOW}Step 5: Verifying installation...${NC}"

# Check if server appears in list
sleep 2  # Give it a moment to initialize

if ! check_mcp_installed; then
    echo -e "${RED}✗ MCP server not found in list${NC}"
    exit 1
else
    echo -e "${GREEN}✓ MCP server appears in list${NC}"
fi

# Check if server is connected
if ! check_mcp_connected; then
    echo -e "${YELLOW}⚠ MCP server added but not connected${NC}"
    echo "  This is normal - it will connect when Claude needs it"
else
    echo -e "${GREEN}✓ MCP server is connected${NC}"
fi

# Step 6: Test with a sample process
echo ""
echo -e "${YELLOW}Step 6: Creating test process...${NC}"

TEST_ID="install-test-$(date +%s)"
"$SCRIPT_DIR/track-it" --id "$TEST_ID" bash -c "echo 'Installation test output'; echo 'Test error' >&2" 2>&1 | grep -v "^\[track-it\]" || true

if [ -f "$LOG_DIR/$TEST_ID.log" ]; then
    echo -e "${GREEN}✓ Test process tracked successfully${NC}"
    echo "  Process ID: $TEST_ID"
    echo "  Log files created in: $LOG_DIR"
else
    echo -e "${RED}✗ Test process tracking failed${NC}"
    exit 1
fi

# Step 7: Test Claude integration
echo ""
echo -e "${YELLOW}Step 7: Testing Claude integration...${NC}"

echo "Attempting to query MCP server from Claude..."

# Try to use Claude to list processes (may need permissions)
TEST_OUTPUT=$(timeout 10 claude -p "Can you check if the MCP tool list_processes exists? Just say YES or NO" 2>&1 || echo "TIMEOUT")

if echo "$TEST_OUTPUT" | grep -qi "yes\|permission\|grant"; then
    echo -e "${GREEN}✓ Claude can see the MCP tool${NC}"
    echo "  Note: You may need to grant permissions when using it"
elif echo "$TEST_OUTPUT" | grep -qi "no"; then
    echo -e "${YELLOW}⚠ Claude doesn't see the MCP tool yet${NC}"
    echo "  Try restarting Claude or granting permissions"
elif echo "$TEST_OUTPUT" | grep -qi "timeout"; then
    echo -e "${YELLOW}⚠ Claude query timed out${NC}"
    echo "  The MCP server is installed but may need Claude restart"
else
    echo -e "${YELLOW}⚠ Could not determine Claude integration status${NC}"
fi

# Step 8: Final verification summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Summary${NC}"
echo -e "${BLUE}========================================${NC}"

# Run final checks
CHECKS_PASSED=0
CHECKS_TOTAL=5

echo ""
echo "Final verification:"

# Check 1: MCP in list
if check_mcp_installed; then
    echo -e "${GREEN}✓ MCP server is installed${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ MCP server not in list${NC}"
fi

# Check 2: Log directory
if [ -d "$LOG_DIR" ]; then
    echo -e "${GREEN}✓ Log directory exists${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ Log directory missing${NC}"
fi

# Check 3: Test process exists
if [ -f "$LOG_DIR/$TEST_ID.log" ]; then
    echo -e "${GREEN}✓ Test process was tracked${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ Test process not tracked${NC}"
fi

# Check 4: Database exists
if [ -f "$SCRIPT_DIR/process_registry.db" ]; then
    echo -e "${GREEN}✓ Process registry database exists${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ Registry database missing${NC}"
fi

# Check 5: track-it is executable
if [ -x "$SCRIPT_DIR/track-it" ]; then
    echo -e "${GREEN}✓ track-it command is executable${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ track-it is not executable${NC}"
fi

echo ""
echo -e "Result: ${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed"

if [ $CHECKS_PASSED -eq $CHECKS_TOTAL ]; then
    echo -e "${GREEN}✅ Installation SUCCESSFUL!${NC}"
    echo ""
    echo "You can now:"
    echo "  1. Track processes: $SCRIPT_DIR/track-it <command>"
    echo "  2. Query in Claude: 'Show my tracked processes'"
    echo ""
    echo "Test process created: $TEST_ID"
    echo "Try in Claude: list_processes(process_id='$TEST_ID')"
else
    echo -e "${YELLOW}⚠️  Installation completed with warnings${NC}"
    echo ""
    echo "Some checks failed but the MCP server may still work."
    echo "Try running: $SCRIPT_DIR/test-mcp-in-claude.sh"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
