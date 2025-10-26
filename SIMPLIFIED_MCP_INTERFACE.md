# Simplified MCP Process Wrapper Interface

## Philosophy
Instead of providing multiple specialized tools for reading logs, searching, tailing, etc., we provide a single `list_processes` tool that returns all necessary information including **full absolute paths** to log files. Claude can then use its native `Read` tool to access any log file directly.

## Single MCP Tool: `list_processes`

### Description
Lists all tracked processes with their metadata and full paths to all log files.

### Parameters
- `status` (optional): Filter by process status (`"running"`, `"completed"`, `"failed"`)
- `limit` (optional): Maximum number of processes to return (newest first)
- `process_id` (optional): Get information for a specific process ID

### Returns
For each process:
- Process ID
- Command executed
- Status (running/completed/failed)
- PID (if available)
- Start timestamp
- Completion timestamp (if completed)
- Exit code (if completed)
- Working directory
- **Full absolute paths to all log files:**
  - Combined log (`.log`)
  - Stdout log (`.stdout.log`)
  - Stderr log (`.stderr.log`)

## Example Usage

### Step 1: Human starts a process
```bash
./track-it-clean --id data-processor python process_data.py --verbose
```

### Step 2: Claude queries processes via MCP
```python
# Using the MCP tool
list_processes(status="running")
```

### Step 3: MCP returns full paths
```
Found 1 process(es):
============================================================
Process ID: data-processor
Command: python process_data.py --verbose
Status: running
PID: 12345
Started: 2025-10-26T14:45:00.123456

Log Files:
  Combined: /home/user/project/process_logs/data-processor.log
  Stdout: /home/user/project/process_logs/data-processor.stdout.log
  Stderr: /home/user/project/process_logs/data-processor.stderr.log
============================================================
```

### Step 4: Claude reads logs directly
```python
# Claude can now use its native Read tool with the full paths
Read("/home/user/project/process_logs/data-processor.stderr.log")

# Or use Grep to search
Grep(
    path="/home/user/project/process_logs/data-processor.stdout.log",
    pattern="ERROR.*database"
)

# Or use Bash to tail
Bash("tail -n 50 /home/user/project/process_logs/data-processor.log")
```

## Benefits of This Approach

### 1. **Simplicity**
- Only ONE MCP tool to maintain
- No duplication of file reading functionality
- Cleaner, smaller codebase

### 2. **Flexibility**
- Claude can use all its native tools (Read, Grep, Bash) on the logs
- No need to re-implement search, tail, etc. in MCP
- Claude can combine logs with other file operations

### 3. **Power**
- Claude has full access to its rich file manipulation toolkit
- Can pipe logs through bash commands
- Can compare multiple log files
- Can use advanced grep patterns

### 4. **Maintenance**
- Less code to maintain
- No need to update MCP tools when Claude gets new file capabilities
- Single source of truth (the registry)

## Implementation Files

### Core Components
1. **`track-it`** - CLI wrapper that starts processes and creates logs
2. **`process_registry.py`** - SQLite registry for process metadata
3. **`mcp_server.py`** - Simplified MCP server (ONE tool only)

### Configuration
- `MCP_PROCESS_WRAPPER_LOG_DIR` - Where logs are stored (default: `./process_logs`)
- `MCP_PROCESS_REGISTRY_DB` - SQLite database path (default: `./process_registry.db`)

## Complete Workflow Example

```bash
# 1. Human starts a web server
$ ./track-it-clean --id web-server python -m http.server 8000

# 2. Claude lists processes (via MCP)
> list_processes(process_id="web-server")
Returns: Full paths to all log files

# 3. Claude analyzes stderr for errors (using native tools)
> Read("/home/user/project/process_logs/web-server.stderr.log")

# 4. Claude searches for specific patterns (using native Grep)
> Grep(
    path="/home/user/project/process_logs/web-server.stdout.log",
    pattern="GET.*404"
  )

# 5. Claude monitors latest activity (using native Bash)
> Bash("tail -f /home/user/project/process_logs/web-server.log")
```

## Why This Is Better

Traditional MCP approach:
- 6+ specialized tools (read_log, tail_log, search_log, etc.)
- Duplicate functionality with Claude's native tools
- Complex API to maintain
- Limited to pre-defined operations

Simplified approach:
- 1 tool that provides paths
- Leverages Claude's powerful native file tools
- No artificial limitations
- Future-proof (works with any new Claude file capabilities)

## Summary

By simplifying the MCP interface to just provide process information and file paths, we:
1. Reduce complexity
2. Increase flexibility
3. Leverage Claude's existing capabilities
4. Create a more maintainable system

Claude already knows how to read files, search them, tail them, and analyze them. We just need to tell Claude WHERE the files are - not HOW to read them!
