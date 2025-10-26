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
    # Get absolute paths for log files
    log_dir = Path(os.getenv("MCP_PROCESS_WRAPPER_LOG_DIR", "./process_logs")).resolve()

    result = {
        "process_id": process["process_id"],
        "command": process["command"],
        "status": process["status"],
        "pid": process.get("pid"),
        "started_at": process["started_at"],
        "completed_at": process.get("completed_at"),
        "exit_code": process.get("exit_code"),
        "working_dir": process.get("working_dir"),
        "logs": {"combined": str(Path(process["log_file"]).resolve()) if process.get("log_file") else None},
    }

    # Add separate stream logs if available
    if process.get("stdout_log"):
        result["logs"]["stdout"] = str(Path(process["stdout_log"]).resolve())

    if process.get("stderr_log"):
        result["logs"]["stderr"] = str(Path(process["stderr_log"]).resolve())

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
            description="List all tracked processes with their status and full paths to log files. Claude can read the log files directly using the provided paths.",
            inputSchema={
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "description": "Optional filter by status",
                        "enum": ["running", "completed", "failed"],
                    },
                    "limit": {
                        "type": "number",
                        "description": "Maximum number of processes to return (newest first)",
                    },
                    "process_id": {
                        "type": "string",
                        "description": "Optional: get info for a specific process ID",
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
            output = f"""Process: {formatted['process_id']}
Command: {formatted['command']}
Status: {formatted['status']}
PID: {formatted.get('pid', 'N/A')}
Started: {formatted['started_at']}
Completed: {formatted.get('completed_at', 'N/A')}
Exit Code: {formatted.get('exit_code', 'N/A')}
Working Dir: {formatted.get('working_dir', 'N/A')}

Log Files:
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
            return [TextContent(type="text", text="No processes found.")]

        # Format all processes
        formatted_processes = [format_process(p) for p in processes]

        # Create summary output
        output_lines = [f"Found {len(formatted_processes)} process(es):\n"]

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

        # Also include a tip for Claude
        output_lines.append(
            "\nTip: You can read any log file directly using the Read tool with the full path provided above."
        )

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
