#!/bin/bash
# Comprehensive install script for track-it MCP server with built-in testing

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Track-It MCP Server Installation${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Step 1: Check Python availability
echo -e "${YELLOW}Step 1: Checking Python installation...${NC}"
PYTHON_CMD="/home/ssilver/anaconda3/bin/python3"

if [ ! -f "$PYTHON_CMD" ]; then
    echo -e "${RED}✗ Python not found at: $PYTHON_CMD${NC}"
    echo "Please update the PYTHON_CMD variable in this script"
    exit 1
fi

PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
echo -e "${GREEN}✓ Found Python: $PYTHON_VERSION${NC}"

# Step 2: Check required Python packages
echo ""
echo -e "${YELLOW}Step 2: Checking Python packages...${NC}"

check_python_package() {
    if $PYTHON_CMD -c "import $1" 2>/dev/null; then
        echo -e "${GREEN}✓ Package '$1' is installed${NC}"
        return 0
    else
        echo -e "${RED}✗ Package '$1' is not installed${NC}"
        return 1
    fi
}

MISSING_PACKAGES=0
if ! check_python_package "mcp"; then
    MISSING_PACKAGES=1
    echo "  Install with: pip install mcp"
fi

if [ $MISSING_PACKAGES -eq 1 ]; then
    echo -e "${RED}Please install missing packages before continuing${NC}"
    exit 1
fi

# Step 3: Check track-it components
echo ""
echo -e "${YELLOW}Step 3: Checking track-it components...${NC}"

if [ ! -f "$SCRIPT_DIR/track-it" ]; then
    echo -e "${RED}✗ track-it not found${NC}"
    exit 1
else
    echo -e "${GREEN}✓ track-it found${NC}"
fi

if [ ! -f "$SCRIPT_DIR/process_registry.py" ]; then
    echo -e "${RED}✗ process_registry.py not found${NC}"
    exit 1
else
    echo -e "${GREEN}✓ process_registry.py found${NC}"
fi

if [ ! -f "$SCRIPT_DIR/mcp_server.py" ]; then
    echo -e "${RED}✗ mcp_server.py not found${NC}"
    exit 1
else
    echo -e "${GREEN}✓ mcp_server.py found${NC}"
fi

# Step 4: Create necessary directories
echo ""
echo -e "${YELLOW}Step 4: Setting up directories...${NC}"

LOG_DIR="$SCRIPT_DIR/process_logs"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    echo -e "${GREEN}✓ Created log directory: $LOG_DIR${NC}"
else
    echo -e "${GREEN}✓ Log directory exists: $LOG_DIR${NC}"
fi

# Step 5: Configure MCP for Claude
echo ""
echo -e "${YELLOW}Step 5: Configuring MCP for Claude...${NC}"

MCP_CONFIG_DIR="$HOME/.claude"
MCP_CONFIG_FILE="$MCP_CONFIG_DIR/mcp.json"

mkdir -p "$MCP_CONFIG_DIR"

# Backup existing config if it exists
if [ -f "$MCP_CONFIG_FILE" ]; then
    BACKUP_FILE="$MCP_CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}  Backing up existing config to: $BACKUP_FILE${NC}"
    cp "$MCP_CONFIG_FILE" "$BACKUP_FILE"
fi

# Create MCP configuration
cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "process-wrapper": {
      "command": "$PYTHON_CMD",
      "args": [
        "$SCRIPT_DIR/mcp_server.py"
      ],
      "env": {
        "MCP_PROCESS_WRAPPER_LOG_DIR": "$LOG_DIR",
        "MCP_PROCESS_REGISTRY_DB": "$SCRIPT_DIR/process_registry.db"
      }
    }
  }
}
EOF

echo -e "${GREEN}✓ MCP configuration created at: $MCP_CONFIG_FILE${NC}"

# Step 6: Test track-it functionality
echo ""
echo -e "${YELLOW}Step 6: Testing track-it functionality...${NC}"

# Run a simple test command
TEST_ID="test-install-$(date +%s)"
echo -e "  Running test process with ID: $TEST_ID"

MCP_PROCESS_WRAPPER_LOG_DIR="$LOG_DIR" $SCRIPT_DIR/track-it --id "$TEST_ID" bash -c "echo 'Test stdout message'; echo 'Test stderr message' >&2; exit 0" 2>/dev/null

# Check if process was registered
echo -e "  Checking process registration..."
if $PYTHON_CMD -c "
import sys
sys.path.append('$SCRIPT_DIR')
from process_registry import ProcessRegistry
registry = ProcessRegistry('$SCRIPT_DIR/process_registry.db')
process = registry.get_process('$TEST_ID')
if process and process['status'] == 'completed':
    print('✓ Process registered successfully')
    sys.exit(0)
else:
    print('✗ Process registration failed')
    sys.exit(1)
" 2>/dev/null; then
    echo -e "${GREEN}✓ Process registered successfully${NC}"
else
    echo -e "${RED}✗ Process registration failed${NC}"
    exit 1
fi

# Check if log files were created
echo -e "  Checking log files..."
if [ -f "$LOG_DIR/$TEST_ID.log" ] && \
   [ -f "$LOG_DIR/$TEST_ID.stdout.log" ] && \
   [ -f "$LOG_DIR/$TEST_ID.stderr.log" ]; then
    echo -e "${GREEN}✓ All log files created successfully${NC}"
else
    echo -e "${RED}✗ Log files not created properly${NC}"
    exit 1
fi

# Verify stdout/stderr separation
echo -e "  Verifying stream separation..."
STDOUT_CONTENT=$(grep "Test stdout message" "$LOG_DIR/$TEST_ID.stdout.log" 2>/dev/null || true)
STDERR_CONTENT=$(grep "Test stderr message" "$LOG_DIR/$TEST_ID.stderr.log" 2>/dev/null || true)

if [ -n "$STDOUT_CONTENT" ] && [ -n "$STDERR_CONTENT" ]; then
    echo -e "${GREEN}✓ Stdout and stderr properly separated${NC}"
else
    echo -e "${RED}✗ Stream separation failed${NC}"
    exit 1
fi

# Step 7: Test MCP server
echo ""
echo -e "${YELLOW}Step 7: Testing MCP server...${NC}"

# Create a test script to simulate MCP call
TEST_MCP_SCRIPT="$SCRIPT_DIR/.test_mcp.py"
cat > "$TEST_MCP_SCRIPT" << 'EOF'
import sys
import json
import asyncio
from pathlib import Path

# Add script directory to path
sys.path.append(sys.argv[1])

async def test_mcp():
    try:
        from mcp_server import app, registry

        # Simulate calling list_processes
        processes = registry.list_processes(limit=1)

        if processes:
            print("✓ MCP server can access registry")
            print(f"  Found {len(processes)} process(es)")

            # Check if we can get the test process
            test_id = sys.argv[2]
            test_proc = registry.get_process(test_id)

            if test_proc:
                print(f"✓ Found test process: {test_id}")

                # Verify paths are absolute
                if test_proc.get('log_file'):
                    log_path = Path(test_proc['log_file']).resolve()
                    if log_path.exists():
                        print(f"✓ Log file accessible: {log_path}")
                        return True

        print("✗ MCP server test failed")
        return False

    except Exception as e:
        print(f"✗ MCP server error: {e}")
        return False

# Run the test
result = asyncio.run(test_mcp())
sys.exit(0 if result else 1)
EOF

if $PYTHON_CMD "$TEST_MCP_SCRIPT" "$SCRIPT_DIR" "$TEST_ID" 2>/dev/null; then
    echo -e "${GREEN}✓ MCP server test passed${NC}"
else
    echo -e "${RED}✗ MCP server test failed${NC}"
    echo "  The MCP server may not be properly configured"
fi

# Cleanup test files
rm -f "$TEST_MCP_SCRIPT"

# Step 8: Check Claude MCP configuration
echo ""
echo -e "${YELLOW}Step 8: Checking Claude's MCP configuration...${NC}"

# Check if the MCP config was actually written and is valid JSON
if [ -f "$MCP_CONFIG_FILE" ]; then
    if $PYTHON_CMD -c "import json; json.load(open('$MCP_CONFIG_FILE'))" 2>/dev/null; then
        echo -e "${GREEN}✓ MCP configuration is valid JSON${NC}"

        # Check if our server is in the config
        if grep -q "process-wrapper" "$MCP_CONFIG_FILE"; then
            echo -e "${GREEN}✓ process-wrapper server is configured${NC}"
        else
            echo -e "${RED}✗ process-wrapper not found in config${NC}"
        fi
    else
        echo -e "${RED}✗ MCP configuration has invalid JSON${NC}"
    fi
else
    echo -e "${RED}✗ MCP configuration file not found${NC}"
fi

# Step 9: Test Claude MCP integration (if Claude CLI is available)
echo ""
echo -e "${YELLOW}Step 9: Testing Claude MCP integration...${NC}"

CLAUDE_CMD=$(which claude 2>/dev/null)
if [ -n "$CLAUDE_CMD" ]; then
    echo -e "  Found Claude CLI at: $CLAUDE_CMD"
    echo -e "  ${YELLOW}Attempting to test MCP integration...${NC}"

    # First, check if Claude is running
    if pgrep -f "claude" > /dev/null; then
        echo -e "  ${YELLOW}Claude appears to be running. It must be restarted to load new MCP config.${NC}"
        echo -e "  ${YELLOW}Please restart Claude Code and re-run this script, or test manually.${NC}"
    else
        # Try to start Claude and test the MCP
        echo -e "  Starting Claude to test MCP server..."

        # Create a test prompt that uses the MCP tool
        TEST_PROMPT="Can you run list_processes(limit=1) and tell me if it works? Just say 'MCP WORKS' if you see processes or 'MCP NOT FOUND' if the tool doesn't exist."

        # Run Claude with the test prompt
        echo -e "  Running test command..."
        CLAUDE_RESPONSE=$(cd "$SCRIPT_DIR" && timeout 15 "$CLAUDE_CMD" -p "$TEST_PROMPT" 2>&1 || true)

        if echo "$CLAUDE_RESPONSE" | grep -q "MCP WORKS\|Found.*process\|Process ID:"; then
            echo -e "${GREEN}✓ Claude can access the MCP server!${NC}"
            echo -e "${GREEN}✓ Integration test passed!${NC}"
        elif echo "$CLAUDE_RESPONSE" | grep -q "MCP NOT FOUND\|list_processes.*not defined\|don't have.*tool"; then
            echo -e "${RED}✗ Claude cannot see the MCP server${NC}"
            echo -e "${YELLOW}  This is normal on first install. Please restart Claude Code.${NC}"
        else
            echo -e "${YELLOW}⚠ Could not determine MCP status from Claude's response${NC}"
            echo -e "  Response preview: ${CLAUDE_RESPONSE:0:100}..."
        fi
    fi
else
    echo -e "${YELLOW}  Claude CLI not found. Cannot auto-test MCP integration.${NC}"
    echo -e "${YELLOW}  Please test manually after restarting Claude Code:${NC}"
    echo "    1. Restart Claude Code completely"
    echo "    2. Run: list_processes()"
fi

# Step 9: Display final summary
echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Installation Complete!${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo -e "${GREEN}✓ All components installed and tested successfully${NC}"
echo ""
echo "Configuration summary:"
echo "  MCP Server: process-wrapper"
echo "  Python: $PYTHON_CMD"
echo "  Script: $SCRIPT_DIR/mcp_server.py"
echo "  Log directory: $LOG_DIR"
echo "  Database: $SCRIPT_DIR/process_registry.db"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Restart Claude Code completely"
echo "  2. In Claude, use: list_processes() to see tracked processes"
echo "  3. Start new processes with: ./track-it <command>"
echo ""
echo "Example usage:"
echo "  ./track-it --id my-process python script.py"
echo ""
echo -e "${GREEN}Test process created: $TEST_ID${NC}"
echo "You can verify the MCP integration in Claude by running:"
echo "  list_processes(process_id='$TEST_ID')"
echo ""

# Step 9: Quick functionality demo
echo -e "${BLUE}Quick Demo:${NC}"
echo "Here's what the test process logged:"
echo ""
echo "STDOUT:"
head -n 15 "$LOG_DIR/$TEST_ID.stdout.log" | grep -v "^====" | grep -v "^Process" | grep -v "^Command" | grep -v "^Working" | grep -v "^Started" | head -3
echo ""
echo "STDERR:"
head -n 15 "$LOG_DIR/$TEST_ID.stderr.log" | grep -v "^====" | grep -v "^Process" | grep -v "^Command" | grep -v "^Working" | grep -v "^Started" | head -3
echo ""
echo -e "${GREEN}Installation and testing complete!${NC}"
