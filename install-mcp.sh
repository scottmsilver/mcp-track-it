#!/bin/bash
# Install track-it MCP server for Claude Code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_CONFIG_DIR="$HOME/.claude"
MCP_CONFIG_FILE="$MCP_CONFIG_DIR/mcp.json"

echo "Installing track-it MCP server..."
echo ""

# Create .claude directory if it doesn't exist
mkdir -p "$MCP_CONFIG_DIR"

# Backup existing config if it exists
if [ -f "$MCP_CONFIG_FILE" ]; then
    BACKUP_FILE="$MCP_CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing config to: $BACKUP_FILE"
    cp "$MCP_CONFIG_FILE" "$BACKUP_FILE"
fi

# Create or update MCP config
cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "process-wrapper": {
      "command": "python3",
      "args": [
        "$SCRIPT_DIR/mcp_server.py"
      ],
      "env": {
        "MCP_PROCESS_WRAPPER_LOG_DIR": "$SCRIPT_DIR/process_logs",
        "MCP_PROCESS_REGISTRY_DB": "$SCRIPT_DIR/process_registry.db"
      }
    }
  }
}
EOF

echo ""
echo "✓ MCP config created at: $MCP_CONFIG_FILE"
echo ""
echo "Configuration:"
echo "  - Server name: process-wrapper"
echo "  - Python: python3"
echo "  - Script: $SCRIPT_DIR/mcp_server.py"
echo "  - Log dir: $SCRIPT_DIR/process_logs"
echo "  - Database: $SCRIPT_DIR/process_registry.db"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code completely"
echo "  2. Run: /mcp to verify the server is loaded"
echo "  3. Use track-it to start processes: ./track-it <command>"
echo "  4. Ask Claude to list processes or check logs"
echo ""
