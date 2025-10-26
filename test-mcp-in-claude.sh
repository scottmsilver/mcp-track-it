#!/bin/bash
# Test if Claude can see and use the MCP server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Testing MCP Server in Claude${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check if Claude CLI is available
CLAUDE_CMD=$(which claude 2>/dev/null)
if [ -z "$CLAUDE_CMD" ]; then
    echo -e "${RED}✗ Claude CLI not found${NC}"
    echo "Please install Claude Code or ensure it's in your PATH"
    exit 1
fi

echo -e "${GREEN}✓ Found Claude CLI at: $CLAUDE_CMD${NC}"

# Check if Claude is currently running
if pgrep -f "claude" > /dev/null; then
    echo -e "${YELLOW}⚠ Claude appears to be running${NC}"
    echo "For best results, restart Claude Code before running this test"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Test cancelled"
        exit 0
    fi
fi

# Test 1: Check if MCP tool exists
echo ""
echo -e "${YELLOW}Test 1: Checking if MCP tool is available...${NC}"

TEST1_RESPONSE=$(cd "$SCRIPT_DIR" && timeout 20 "$CLAUDE_CMD" -p "Can you check if you have access to a tool called list_processes? Just respond with YES or NO." 2>&1 || true)

if echo "$TEST1_RESPONSE" | grep -qi "yes"; then
    echo -e "${GREEN}✓ Claude reports having access to list_processes tool${NC}"
elif echo "$TEST1_RESPONSE" | grep -qi "no"; then
    echo -e "${RED}✗ Claude reports NOT having access to list_processes tool${NC}"
    echo "Please check:"
    echo "  1. Is ~/.claude/mcp.json configured correctly?"
    echo "  2. Was Claude Code restarted after installation?"
    exit 1
else
    echo -e "${YELLOW}⚠ Unclear response from Claude${NC}"
    echo "Response: ${TEST1_RESPONSE:0:200}..."
fi

# Test 2: Try to list processes
echo ""
echo -e "${YELLOW}Test 2: Attempting to list processes...${NC}"

TEST2_RESPONSE=$(cd "$SCRIPT_DIR" && timeout 20 "$CLAUDE_CMD" -p "Please run list_processes(limit=2) and show me the output." 2>&1 || true)

if echo "$TEST2_RESPONSE" | grep -q "Process ID:\|Found.*process\|process_id"; then
    echo -e "${GREEN}✓ Claude successfully called list_processes!${NC}"
    echo ""
    echo "Sample output:"
    echo "$TEST2_RESPONSE" | grep -A5 "Process ID:" | head -10

    # Test 3: Try to read a log file
    echo ""
    echo -e "${YELLOW}Test 3: Testing log file reading...${NC}"

    # Extract a log path from the response
    LOG_PATH=$(echo "$TEST2_RESPONSE" | grep -oP '(?<=Combined: ).*?\.log' | head -1)

    if [ -n "$LOG_PATH" ]; then
        echo "Found log path: $LOG_PATH"

        TEST3_RESPONSE=$(cd "$SCRIPT_DIR" && timeout 20 "$CLAUDE_CMD" -p "Please read the first 5 lines of this file: $LOG_PATH" 2>&1 || true)

        if echo "$TEST3_RESPONSE" | grep -q "Process ID:\|====\|Command:"; then
            echo -e "${GREEN}✓ Claude can read log files!${NC}"
        else
            echo -e "${YELLOW}⚠ Claude might not be able to read log files${NC}"
        fi
    fi

elif echo "$TEST2_RESPONSE" | grep -qi "don't have\|not defined\|no.*tool\|error"; then
    echo -e "${RED}✗ Claude cannot access the MCP server${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check ~/.claude/mcp.json exists and is valid:"
    echo "   cat ~/.claude/mcp.json | python3 -m json.tool"
    echo ""
    echo "2. Verify paths in the config are correct"
    echo ""
    echo "3. Completely restart Claude Code (not just reload)"
    echo ""
    echo "4. Check Claude's developer console for errors (F12)"
    exit 1
else
    echo -e "${YELLOW}⚠ Unexpected response from Claude${NC}"
    echo "Response preview:"
    echo "$TEST2_RESPONSE" | head -10
fi

# Test 4: Create a new process and verify Claude can see it
echo ""
echo -e "${YELLOW}Test 4: Creating test process and verifying Claude can see it...${NC}"

TEST_ID="mcp-test-$(date +%s)"
echo "Creating test process: $TEST_ID"

"$SCRIPT_DIR/track-it" --id "$TEST_ID" bash -c "echo 'MCP test output'; echo 'MCP test error' >&2" >/dev/null 2>&1

sleep 1

TEST4_RESPONSE=$(cd "$SCRIPT_DIR" && timeout 20 "$CLAUDE_CMD" -p "Please run list_processes(process_id='$TEST_ID') and tell me the status." 2>&1 || true)

if echo "$TEST4_RESPONSE" | grep -q "$TEST_ID\|completed\|MCP test"; then
    echo -e "${GREEN}✓ Claude can see newly created processes!${NC}"
else
    echo -e "${YELLOW}⚠ Claude might not see new processes${NC}"
fi

# Final summary
echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Test Results Summary${NC}"
echo -e "${BLUE}=====================================${NC}"

if echo "$TEST2_RESPONSE" | grep -q "Process ID:"; then
    echo -e "${GREEN}✅ MCP Server Integration: WORKING${NC}"
    echo ""
    echo "Claude can:"
    echo "  ✓ Access the list_processes tool"
    echo "  ✓ Query the process registry"
    echo "  ✓ Return process information"
    echo "  ✓ Provide log file paths"
    echo ""
    echo "You can now use track-it to monitor any process and Claude will be able to see it!"
else
    echo -e "${RED}❌ MCP Server Integration: NOT WORKING${NC}"
    echo ""
    echo "Please follow the troubleshooting steps above"
fi

echo ""
echo "Test complete!"
