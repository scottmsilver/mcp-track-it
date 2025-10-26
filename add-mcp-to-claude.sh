#!/bin/bash
# Add MCP server to Claude using the CLI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Adding process-wrapper MCP server to Claude..."

# Remove any existing process-wrapper server
claude mcp remove process-wrapper 2>/dev/null || true

# Add the MCP server using Claude CLI
claude mcp add --transport stdio process-wrapper \
  --env MCP_PROCESS_WRAPPER_LOG_DIR="$SCRIPT_DIR/process_logs" \
  --env MCP_PROCESS_REGISTRY_DB="$SCRIPT_DIR/process_registry.db" \
  -- /home/ssilver/anaconda3/bin/python3 "$SCRIPT_DIR/mcp_server.py"

echo ""
echo "Checking if server was added..."
claude mcp list

echo ""
echo "Getting server details..."
claude mcp get process-wrapper

echo ""
echo "Testing the MCP server..."
echo "Running: claude -p 'Can you run list_processes()?'"
claude -p "Can you run list_processes()?" 2>&1 | head -20

echo ""
echo "Done! The MCP server should now be available in Claude."
