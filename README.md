# MCP Process Wrapper

A minimalist MCP (Model Context Protocol) server that enables Claude to monitor processes with independent stdout/stderr tracking.

## Architecture

```
User: track-it python app.py
         ↓
   [track-it wrapper]
         ↓
   ┌─────────────┬──────────────┐
   │             │              │
SQLite DB    Log Files    Running Process
   │             │
   └─────────────┴──────────────
              ↓
      [MCP Server] ← Claude queries
```

**Key Components:**

1. **`track-it`** - CLI wrapper you run (like ptrace/dtrace)
2. **SQLite Registry** - Multi-process safe process database
3. **Log Files** - Timestamped stdout/stderr captures
4. **MCP Server** - Read-only interface for Claude

## Features

- **Simple wrapper** - Just prepend `track-it` to any command
- **Multi-process safe** - SQLite handles concurrent access
- **Persistent** - Survives restarts, data stored on disk
- **Searchable logs** - Pattern matching with regex support
- **Read-only MCP** - Claude can only observe, not execute

## Installation

1. Install dependencies:

```bash
cd mcp-process-wrapper
pip install mcp
# SQLite is built into Python, no extra install needed
```

2. Make `track-it` executable:

```bash
chmod +x track-it
```

## Usage

### Running Processes with track-it

Just prepend `track-it` to your command:

```bash
# Basic usage
./track-it python my_app.py --foo --bar

# Custom process ID
./track-it --id my-service python app.py

# Custom working directory
./track-it --dir /path/to/workdir ./script.sh
```

**Output:**
```
[track-it] Process started: proc_20250126_143022_123456 (PID: 12345)
[track-it] Log file: ./process_logs/proc_20250126_143022_123456.log
[track-it] Press Ctrl+C to stop

<your program output here>

[track-it] Process completed: proc_20250126_143022_123456
[track-it] Exit code: 0
```

### Connecting Claude via MCP

Add to your Claude Code `.claude/mcp.json`:

```json
{
  "mcpServers": {
    "process-wrapper": {
      "command": "python",
      "args": ["/home/ssilver/development/invoice2/mcp-process-wrapper/process_wrapper_mcp.py"],
      "env": {
        "MCP_PROCESS_WRAPPER_LOG_DIR": "/home/ssilver/development/invoice2/process_logs",
        "MCP_PROCESS_REGISTRY_DB": "/home/ssilver/development/invoice2/mcp-process-wrapper/process_registry.db"
      }
    }
  }
}
```

Restart Claude Code to load the MCP server.

### Claude's Tools

Once configured, Claude can use these tools:

#### 1. `list_processes`
List all tracked processes with optional filtering:

```
List all running processes
List failed processes
List last 10 processes
```

#### 2. `get_process_info`
Get detailed info about a specific process:

```
Get info for process proc_20250126_143022_123456
```

#### 3. `read_log`
Read complete log file:

```
Read the log for proc_20250126_143022_123456
```

#### 4. `tail_log`
Get last N lines of log:

```
Show last 100 lines of proc_20250126_143022_123456
```

#### 5. `search_log`
Search logs with regex and context:

```
Search for "error" in proc_20250126_143022_123456
Search for "ERROR.*failed" with 5 context lines
```

## Example Workflow

```bash
# Terminal 1: Start your app with track-it
./track-it python my_web_app.py

# Terminal 2: Ask Claude in Claude Code
User: "Can you check if my web app is running and show me any errors?"

Claude: [Uses list_processes to see running processes]
        [Uses search_log to find errors]

        "Your app is running (PID 12345). I found 3 errors in the logs:
        - Line 45: Connection timeout to database
        - Line 67: Missing environment variable API_KEY
        - Line 89: File not found: config.json"
```

## Configuration

Environment variables:

- **`MCP_PROCESS_WRAPPER_LOG_DIR`** - Directory for log files (default: `./process_logs`)
- **`MCP_PROCESS_REGISTRY_DB`** - Path to SQLite database (default: `./process_registry.db`)

## Multi-Process Safety

SQLite provides automatic locking for concurrent access:

- **WAL mode** - Readers don't block writers
- **10-second timeout** - Waits for locks instead of failing
- **Atomic operations** - No corrupted data from simultaneous writes

You can safely:
- Run multiple `track-it` processes simultaneously
- Query via Claude while processes are being added/updated
- Have multiple Claude instances querying the same registry

## Log File Format

Each process gets a timestamped log file:

```
============================================================
Process ID: proc_20250126_143022_123456
Command: python my_app.py --foo --bar
Working directory: /home/user/project
Started at: 2025-01-26T14:30:22.123456
============================================================

<stdout and stderr merged here>

============================================================
Process exited with code 0
Completed at: 2025-01-26T14:32:15.789012
============================================================
```

## Database Schema

SQLite database stores:

```sql
CREATE TABLE processes (
    process_id TEXT PRIMARY KEY,
    command TEXT NOT NULL,
    pid INTEGER,
    status TEXT NOT NULL,      -- 'running', 'completed', 'failed'
    log_file TEXT NOT NULL,
    working_dir TEXT,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    exit_code INTEGER
)
```

Indexed on `status` and `started_at` for fast queries.

## Files Created

```
mcp-process-wrapper/
├── track-it                    # CLI wrapper (you run this)
├── process_registry.py         # SQLite registry module
├── process_wrapper_mcp.py      # MCP server (Claude uses this)
├── process_registry.db         # SQLite database (auto-created)
├── process_logs/               # Log files directory (auto-created)
│   ├── proc_20250126_143022_123456.log
│   └── proc_20250126_143155_789012.log
├── requirements.txt
├── .gitignore
└── README.md
```

## Comparison with Alternatives

| Feature | track-it | supervisord | strace/dtrace |
|---------|----------|-------------|---------------|
| Simple wrapper | ✅ Yes | ❌ Requires config | ✅ Yes |
| Persistent logs | ✅ Yes | ✅ Yes | ❌ No |
| Multi-process safe | ✅ SQLite | ✅ Yes | N/A |
| Claude integration | ✅ Built-in | ⚠️ Via supervisord-mcp | ❌ No |
| Searchable logs | ✅ Built-in | ❌ External tools | ❌ No |
| Zero setup | ✅ Yes | ❌ Config files | ✅ Yes |

## Security

- **Read-only MCP** - Claude cannot start processes, only monitor
- **Local only** - No network access
- **File isolation** - Logs stored in configured directory
- **Process isolation** - Each process has its own log file

## Troubleshooting

**Q: Claude can't see my processes**
- Check `MCP_PROCESS_REGISTRY_DB` points to the same database `track-it` is using
- Restart Claude Code after changing MCP config

**Q: Permission denied on track-it**
```bash
chmod +x track-it
```

**Q: Import error for process_registry**
- Make sure you run the MCP server from the `mcp-process-wrapper` directory
- Or add the directory to PYTHONPATH

**Q: Logs not appearing**
- Check `MCP_PROCESS_WRAPPER_LOG_DIR` is writable
- Ensure directory exists or can be created

## Development

To extend functionality:

1. **Add new columns to DB**: Edit `process_registry.py._init_database()`
2. **Add new MCP tools**: Edit `process_wrapper_mcp.py.list_tools()`
3. **Modify log capture**: Edit `track-it` main loop

## License

MIT - Use freely, modify as needed.
