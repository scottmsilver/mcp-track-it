#!/usr/bin/env python3
"""
Simplified MCP Server for Process Monitoring.

This minimal server provides just one tool - list_processes - which returns
all the information Claude needs including full paths to log files.
Claude can then read the files directly using its built-in file reading capabilities.

Usage:
    python process_wrapper_mcp_simple.py
"""

import os
from pathlib import Path
from typing import Any, Optional

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

from process_registry import ProcessRegistry


def format_process(process: dict[str, Any]) -> dict[str, Any]:
    """
    Format process information with full absolute paths.

    Returns a dictionary with all process details including full paths to logs.
    """

    def resolve_log_path(log_path: Optional[str], working_dir: Optional[str]) -> Optional[str]:
        """Resolve a log path to absolute, handling both old relative and new absolute paths."""
        if not log_path:
            return None

        path = Path(log_path)

        # If already absolute, just return it
        if path.is_absolute():
            return str(path)

        # For relative paths, resolve relative to the working directory where process was started
        if working_dir:
            return str((Path(working_dir) / path).resolve())

        # Fallback: resolve relative to current directory (shouldn't happen with fixed code)
        return str(path.resolve())

    working_dir = process.get("working_dir")

    result = {
        "process_id": process["process_id"],
        "command": process["command"],
        "status": process["status"],
        "pid": process.get("pid"),
        "started_at": process["started_at"],
        "completed_at": process.get("completed_at"),
        "exit_code": process.get("exit_code"),
        "working_dir": working_dir,
        "logs": {"combined": resolve_log_path(process.get("log_file"), working_dir)},
    }

    # Add separate stream logs if available
    if process.get("stdout_log"):
        result["logs"]["stdout"] = resolve_log_path(process.get("stdout_log"), working_dir)

    if process.get("stderr_log"):
        result["logs"]["stderr"] = resolve_log_path(process.get("stderr_log"), working_dir)

    # Flag indicating if streams are separate
    result["has_separate_streams"] = process.get("has_separate_streams", False)

    return result


# Create MCP server
app = Server("process-wrapper-simple")

# Initialize registry
registry = ProcessRegistry()


@app.list_tools()
async def list_tools() -> list[Tool]:
    """List available tools - just one in this simplified version."""
    return [
        Tool(
            name="list_processes",
            description="""List processes that were tracked using the 'track-it' command-line wrapper.

IMPORTANT: If the user mentions they ran something with 'track-it' (e.g., "I ran track-it python script.py" or "I'm tracking my server with track-it"),
use this tool to find and analyze those processes. The user's track-it commands create the processes that this tool lists.

Common user patterns:
- "I tracked X with track-it" → Use list_processes() to find process X
- "track-it --id webserver ..." → Use list_processes(process_id='webserver')
- "Check my tracked processes" → Use list_processes()
- "What did my script output?" → Find the process, then read its logs

Returns process information including:
- Process ID, command, and status (running/completed/failed)
- Full absolute paths to three log files:
  * .log (combined stdout+stderr)
  * .stdout.log (stdout only)
  * .stderr.log (stderr only)
- Timestamps and exit codes

After getting paths from this tool, use your native file tools:
- Read('/path/to/file.log') to read complete logs
- Grep(path='/path/to/file.log', pattern='ERROR') to search
- Bash('tail -f /path/to/file.log') to monitor running processes
- Bash('tail -100 /path/to/file.stderr.log') to check recent errors

Note: This tool only LISTS processes. Users start processes externally with: track-it <command>""",
            inputSchema={
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "description": "Filter by process status: 'running' (still active), 'completed' (exited successfully with code 0), or 'failed' (exited with non-zero code)",
                        "enum": ["running", "completed", "failed"],
                    },
                    "limit": {
                        "type": "number",
                        "description": "Maximum number of processes to return, ordered by start time (newest first). Default: all processes",
                    },
                    "process_id": {
                        "type": "string",
                        "description": "Get info for a specific process by its ID (e.g., 'web-server' or 'proc_20251026_143245_123456'). If provided, other filters are ignored",
                    },
                },
            },
        ),
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent]:
    """Handle tool calls."""
    if name != "list_processes":
        return [TextContent(type="text", text=f"Unknown tool: {name}")]

    try:
        # If specific process_id requested, return just that one
        if arguments.get("process_id"):
            process = registry.get_process(arguments["process_id"])
            if not process:
                return [TextContent(type="text", text=f"Process not found: {arguments['process_id']}")]

            formatted = format_process(process)

            # Create human-readable output
            output = f"""Found tracked process: {formatted['process_id']}
(This process was started with: track-it {formatted['command'][:50]}{'...' if len(formatted['command']) > 50 else ''})

Status: {formatted['status']}
PID: {formatted.get('pid', 'N/A')}
Started: {formatted['started_at']}
Completed: {formatted.get('completed_at', 'N/A')}
Exit Code: {formatted.get('exit_code', 'N/A')}
Working Dir: {formatted.get('working_dir', 'N/A')}

Log Files (use these paths with Read/Grep/Bash tools):
  Combined: {formatted['logs']['combined']}"""

            if formatted.get("has_separate_streams"):
                if formatted["logs"].get("stdout"):
                    output += f"\n  Stdout: {formatted['logs']['stdout']}"
                if formatted["logs"].get("stderr"):
                    output += f"\n  Stderr: {formatted['logs']['stderr']}"

            return [TextContent(type="text", text=output)]

        # Otherwise, list all processes with optional filters
        processes = registry.list_processes(
            status=arguments.get("status"),
            limit=arguments.get("limit"),
        )

        if not processes:
            return [
                TextContent(
                    type="text",
                    text="No tracked processes found.\n\nThe user needs to start processes with: track-it <command>\nExample: track-it python script.py\n\nOnce they run track-it, those processes will appear here.",
                )
            ]

        # Format all processes
        formatted_processes = [format_process(p) for p in processes]

        # Create summary output
        output_lines = [f"Found {len(formatted_processes)} process(es) tracked with 'track-it':\n"]
        output_lines.append("(These are processes the user started with: track-it <command>)\n")

        for proc in formatted_processes:
            output_lines.append(f"{'='*60}")
            output_lines.append(f"Process ID: {proc['process_id']}")
            output_lines.append(f"Command: {proc['command']}")
            output_lines.append(f"Status: {proc['status']}")

            if proc.get("pid"):
                output_lines.append(f"PID: {proc['pid']}")

            output_lines.append(f"Started: {proc['started_at']}")

            if proc.get("completed_at"):
                output_lines.append(f"Completed: {proc['completed_at']}")
                output_lines.append(f"Exit Code: {proc.get('exit_code', 'N/A')}")

            # Show log file paths
            output_lines.append(f"\nLog Files:")
            output_lines.append(f"  Combined: {proc['logs']['combined']}")

            if proc.get("has_separate_streams"):
                if proc["logs"].get("stdout"):
                    output_lines.append(f"  Stdout: {proc['logs']['stdout']}")
                if proc["logs"].get("stderr"):
                    output_lines.append(f"  Stderr: {proc['logs']['stderr']}")

        output_lines.append(f"{'='*60}")

        # Also include helpful examples for Claude
        output_lines.append("\n" + "=" * 60)
        output_lines.append("\nHow to use these log files:")
        output_lines.append("1. Read a complete log: Read('/full/path/to/process.log')")
        output_lines.append("2. Search for errors: Grep(path='/full/path/to/process.stderr.log', pattern='ERROR|FAIL')")
        output_lines.append("3. Monitor live output: Bash('tail -f /full/path/to/process.log')")
        output_lines.append("4. Check last 50 lines: Bash('tail -50 /full/path/to/process.stdout.log')")
        output_lines.append("\nNote: Processes must be started externally with: track-it <command>")

        return [TextContent(type="text", text="\n".join(output_lines))]

    except Exception as e:
        return [TextContent(type="text", text=f"Error: {str(e)}")]


async def main():
    """Run the MCP server."""
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
