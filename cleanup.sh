#!/bin/bash

echo "Cleaning up MCP Process Wrapper - keeping only the final implementation"
echo "========================================================================"
echo ""

# Files to KEEP (the final, clean implementation)
KEEP_FILES=(
    "track-it-clean"                    # Final working track-it with separate streams
    "process_registry_v2.py"            # Enhanced registry with stream support
    "process_wrapper_mcp_simple.py"     # Simplified MCP server (just list_processes)
    "install-mcp.sh"                    # Installation script
    "SIMPLIFIED_MCP_INTERFACE.md"       # Documentation
    "cleanup.sh"                        # This script
    "process_logs"                      # Log directory
    "process_registry.db"               # Database
)

# Files to REMOVE (old/experimental versions)
REMOVE_FILES=(
    "track-it"                          # Original version (no stream separation)
    "track-it-v2"                       # Experimental version
    "track-it-independent"              # Another experimental version
    "process_registry.py"               # Old registry without stream support
    "process_wrapper_mcp.py"            # Old complex MCP with 6+ tools
    "process_wrapper_mcp_v2.py"         # Complex MCP with stream support
    "MCP_INTERFACE_DOCS.md"             # Old documentation for complex interface
)

echo "Files to KEEP:"
for file in "${KEEP_FILES[@]}"; do
    if [ -e "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ⚠ $file (not found)"
    fi
done

echo ""
echo "Files to REMOVE:"
for file in "${REMOVE_FILES[@]}"; do
    if [ -e "$file" ]; then
        echo "  ✗ $file"
    else
        echo "  - $file (already gone)"
    fi
done

echo ""
read -p "Do you want to proceed with cleanup? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing old files..."
    for file in "${REMOVE_FILES[@]}"; do
        if [ -e "$file" ]; then
            rm -f "$file"
            echo "  Removed: $file"
        fi
    done

    # Update install script to use the simple MCP server
    echo ""
    echo "Updating install-mcp.sh to use simplified server..."
    sed -i 's/process_wrapper_mcp.py/process_wrapper_mcp_simple.py/g' install-mcp.sh

    # Rename track-it-clean to just track-it for simplicity
    echo "Renaming track-it-clean to track-it..."
    mv track-it-clean track-it

    # Update the registry import in track-it
    sed -i 's/from process_registry_v2/from process_registry/g' track-it

    # Rename process_registry_v2.py to process_registry.py
    echo "Renaming process_registry_v2.py to process_registry.py..."
    mv process_registry_v2.py process_registry.py

    # Update the import in the MCP server
    sed -i 's/from process_registry_v2/from process_registry/g' process_wrapper_mcp_simple.py

    echo ""
    echo "✅ Cleanup complete! Final structure:"
    echo ""
    echo "Core files:"
    echo "  - track-it                      # CLI wrapper for starting processes"
    echo "  - process_registry.py           # SQLite registry with stream support"
    echo "  - process_wrapper_mcp_simple.py # Simple MCP server (one tool only)"
    echo "  - install-mcp.sh                # Installation script"
    echo ""
    echo "The system is now clean and ready to use!"
else
    echo "Cleanup cancelled."
fi
