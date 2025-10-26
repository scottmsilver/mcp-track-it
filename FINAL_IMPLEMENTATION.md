# Track-It MCP Process Wrapper - Final Implementation

## Overview
A clean, minimalist system that allows Claude to monitor processes with **independent stdout/stderr tracking** through a single MCP tool.

## Final Architecture

### Only 3 Core Files:

1. **`track-it`** - CLI wrapper that starts and tracks processes
   - Creates independent copies of stdout/stderr without interfering with the process
   - Logs to three files: `.log` (combined), `.stdout.log`, `.stderr.log`
   - No environment variables required in the tracked process

2. **`process_registry.py`** - SQLite registry for process metadata
   - Tracks process ID, command, status, timestamps, exit codes
   - Stores paths to all three log files
   - Multi-process safe with WAL mode

3. **`mcp_server.py`** - Minimalist MCP server
   - Provides just ONE tool: `list_processes`
   - Returns full absolute paths to all log files
   - Claude uses its native tools (Read, Grep, Bash) for everything else

## Key Design Principles

✅ **Simplicity** - One MCP tool instead of 6+
✅ **Non-invasive** - Process runs exactly as if track-it wasn't there
✅ **Independent streams** - Separate stdout/stderr capture
✅ **Leverage Claude** - Use Claude's existing file tools, don't reinvent them

## Installation & Usage

### Install MCP Server
```bash
./install-mcp.sh
# Restart Claude Code
```

### Start a Process
```bash
./track-it --id my-process python script.py
```

### From Claude's Perspective
```python
# 1. Get process info via MCP
list_processes(process_id="my-process")
# Returns: Full paths to all log files

# 2. Read logs directly
Read("/full/path/to/my-process.stderr.log")

# 3. Search with patterns
Grep(path="/full/path/to/my-process.stdout.log", pattern="ERROR")

# 4. Use any bash command
Bash("tail -f /full/path/to/my-process.log")
```

## What We Removed
- ❌ 6+ specialized MCP tools (read_log, search_log, tail_log, etc.)
- ❌ Complex multi-tool MCP servers
- ❌ Duplicate file reading logic
- ❌ Multiple experimental versions

## Why This Is Better
- **Maintainable**: ~300 lines of code instead of 1000+
- **Powerful**: Claude can use ALL its file tools, not just pre-defined operations
- **Future-proof**: Works with any new Claude capabilities
- **Clean**: Single responsibility - MCP provides paths, Claude handles files

## Files in Final Implementation
```
track-it                 # Start & track processes
process_registry.py      # SQLite metadata store
mcp_server.py           # MCP server (1 tool)
install-mcp.sh          # Installation script
install-and-test.sh     # Installation with testing
Documentation files...
```

## The Core Insight
Claude doesn't need us to teach it how to read files - it already knows!
We just need to tell Claude WHERE the files are, not HOW to read them.

---

*Clean. Simple. Powerful.*
