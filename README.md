# track-it: MCP Process Wrapper

A lightweight process tracker that enables Claude to monitor and inspect running processes through the Model Context Protocol (MCP).

## Features

- **🚀 Simple CLI wrapper** - Just prepend `track-it` to any command
- **🔍 Environment variable support** - Pass env vars to tracked processes
- **📝 Separate stdout/stderr logs** - Independent capture of output streams
- **💾 Persistent SQLite storage** - Survives restarts, queryable history
- **🔒 Read-only MCP interface** - Claude can observe but not execute
- **📊 Real-time monitoring** - Tail logs of running processes
- **🛡️ Signal handling** - Clean shutdown with Ctrl+C

## Quick Start

### Installation

1. Clone the repository:
```bash
git clone https://github.com/scottmsilver/mcp-track-it.git
cd mcp-track-it
```

2. Install MCP dependency:
```bash
pip install mcp
```

3. Run the installer:
```bash
./install-and-test.sh
```

This will:
- Check Python installation
- Test the track-it wrapper
- Configure Claude's MCP settings
- Run a test process to verify everything works

### Basic Usage

```bash
# Simple command
./track-it echo "Hello World"

# With custom ID
./track-it --id myapp python server.py

# With environment variables
./track-it PORT=8080 DEBUG=true -- python app.py

# Multiple env vars and options
./track-it --id webserver PORT=3000 HOST=0.0.0.0 -- npm start
```

### Environment Variable Support

The new syntax supports passing environment variables to tracked processes:

```bash
# Format: track-it [options] [ENV=value ...] [--] command [args]

# Examples:
./track-it DATABASE_URL=postgres://localhost/mydb -- python manage.py runserver
./track-it --id worker REDIS_HOST=localhost WORKERS=4 -- python worker.py
```

Use `--` to separate environment variables from the command when needed.

## Claude Integration

Once installed, Claude can monitor your processes using these phrases:

- "List all my tracked processes"
- "Show me the logs for [process-id]"
- "Check if my server is still running"
- "Find any errors in the process logs"

### What Claude Sees

When you run:
```bash
./track-it --id myserver PORT=8080 -- python server.py
```

Claude will see:
- Process ID: `myserver`
- Status: `running` or `completed`
- Full command with arguments
- Environment variables that were set
- Complete stdout/stderr logs
- Exit code when completed

## File Structure

```
mcp-track-it/
├── track-it                    # Main CLI wrapper
├── mcp_server.py              # MCP server for Claude
├── process_registry.py        # SQLite database interface
├── install-and-test.sh        # Main installer
├── process_logs/              # Log files (auto-created)
│   ├── [process-id].log       # Combined stdout+stderr
│   ├── [process-id].stdout.log
│   └── [process-id].stderr.log
└── process_registry.db        # SQLite database (auto-created)
```

## How It Works

1. **track-it wrapper** captures your process output
2. **SQLite database** stores process metadata
3. **Log files** preserve stdout/stderr streams
4. **MCP server** provides read-only access to Claude

```
User runs: track-it python app.py
    ↓
Creates 3 log files + DB entry
    ↓
Process runs with real-time output
    ↓
Claude can query via MCP server
```

## Advanced Configuration

### Custom Log Directory

Set the environment variable:
```bash
export MCP_PROCESS_WRAPPER_LOG_DIR=/path/to/logs
./track-it python app.py
```

### Manual MCP Configuration

If you need to manually configure Claude's MCP settings, add to `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "process-wrapper": {
      "command": "python3",
      "args": ["/path/to/mcp-track-it/mcp_server.py"],
      "env": {
        "MCP_PROCESS_WRAPPER_LOG_DIR": "/path/to/logs",
        "MCP_PROCESS_REGISTRY_DB": "/path/to/process_registry.db"
      }
    }
  }
}
```

## Troubleshooting

**Permission denied when running track-it:**
```bash
chmod +x track-it
```

**Claude can't see processes:**
- Restart Claude Code after installation
- Verify MCP server is listed: Ask Claude to run `/mcp` command

**Process gets stuck when hitting Ctrl+C:**
- Update to the latest version (this bug was fixed)

**Logs not appearing:**
- Check write permissions in the log directory
- Verify disk space is available

## Recent Improvements

- ✅ **Environment variable support** - Pass env vars to tracked processes
- ✅ **Absolute path storage** - Reliable log file access across directories
- ✅ **Fixed signal handling** - Clean shutdown without infinite loops
- ✅ **Better path resolution** - MCP server correctly finds logs from any working directory

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - See LICENSE file for details.

## Author

Created as a lightweight alternative to complex process managers, specifically designed for Claude MCP integration.
