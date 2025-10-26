"""
Enhanced Process Registry with support for separate stdout/stderr logs.

This version maintains backward compatibility while adding support for
tracking separate stdout and stderr log files.
"""

import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Optional


class ProcessRegistry:
    """SQLite-based process registry with enhanced stream tracking."""

    def __init__(self, db_path: Optional[str] = None):
        """
        Initialize the process registry.

        Args:
            db_path: Path to SQLite database file (default: ./process_registry.db)
        """
        if db_path is None:
            db_path = os.getenv(
                "MCP_PROCESS_REGISTRY_DB",
                str(Path(__file__).parent / "process_registry.db"),
            )

        self.db_path = db_path
        self._init_database()

    def _init_database(self):
        """Initialize the database schema if it doesn't exist."""
        with self._get_connection() as conn:
            # Create main table (backward compatible)
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS processes (
                    process_id TEXT PRIMARY KEY,
                    command TEXT NOT NULL,
                    pid INTEGER,
                    status TEXT NOT NULL,
                    log_file TEXT NOT NULL,
                    working_dir TEXT,
                    started_at TEXT NOT NULL,
                    completed_at TEXT,
                    exit_code INTEGER
                )
                """
            )

            # Add new columns for separate logs if they don't exist
            # Use ALTER TABLE to maintain backward compatibility
            cursor = conn.execute("PRAGMA table_info(processes)")
            columns = [row[1] for row in cursor.fetchall()]

            if "stdout_log" not in columns:
                conn.execute("ALTER TABLE processes ADD COLUMN stdout_log TEXT")

            if "stderr_log" not in columns:
                conn.execute("ALTER TABLE processes ADD COLUMN stderr_log TEXT")

            if "has_separate_streams" not in columns:
                conn.execute("ALTER TABLE processes ADD COLUMN has_separate_streams BOOLEAN DEFAULT 0")

            # Create indexes
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_status ON processes(status)
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_started_at ON processes(started_at DESC)
                """
            )
            conn.commit()

    @contextmanager
    def _get_connection(self):
        """
        Get a database connection with proper settings for multi-process access.

        SQLite connection is configured with:
        - WAL mode for better concurrency
        - Longer timeout for busy database
        - Automatic commit on context exit
        """
        conn = sqlite3.connect(self.db_path, timeout=10.0)
        conn.row_factory = sqlite3.Row  # Access columns by name

        # Enable WAL mode for better concurrent access
        conn.execute("PRAGMA journal_mode=WAL")

        try:
            yield conn
        finally:
            conn.close()

    def register_process(
        self,
        process_id: str,
        command: str,
        pid: Optional[int],
        log_file: str,
        working_dir: Optional[str] = None,
        stdout_log: Optional[str] = None,
        stderr_log: Optional[str] = None,
    ) -> None:
        """
        Register a new process with optional separate stream logs.

        Args:
            process_id: Unique identifier for the process
            command: Command being executed
            pid: Process ID (optional)
            log_file: Path to combined log file
            working_dir: Working directory where command is run
            stdout_log: Path to stdout-only log file (optional)
            stderr_log: Path to stderr-only log file (optional)
        """
        has_separate_streams = stdout_log is not None or stderr_log is not None

        with self._get_connection() as conn:
            conn.execute(
                """
                INSERT INTO processes (
                    process_id, command, pid, status, log_file,
                    working_dir, started_at, stdout_log, stderr_log,
                    has_separate_streams
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    process_id,
                    command,
                    pid,
                    "running",
                    log_file,
                    working_dir,
                    datetime.now().isoformat(),
                    stdout_log,
                    stderr_log,
                    has_separate_streams,
                ),
            )
            conn.commit()

    def update_process_status(
        self,
        process_id: str,
        status: str,
        exit_code: Optional[int] = None,
    ) -> None:
        """
        Update process status.

        Args:
            process_id: Process identifier
            status: New status (e.g., 'running', 'completed', 'failed')
            exit_code: Optional exit code if process completed
        """
        with self._get_connection() as conn:
            if status in ("completed", "failed"):
                conn.execute(
                    """
                    UPDATE processes
                    SET status = ?, exit_code = ?, completed_at = ?
                    WHERE process_id = ?
                    """,
                    (status, exit_code, datetime.now().isoformat(), process_id),
                )
            else:
                conn.execute(
                    """
                    UPDATE processes
                    SET status = ?
                    WHERE process_id = ?
                    """,
                    (status, process_id),
                )
            conn.commit()

    def get_process(self, process_id: str) -> Optional[dict]:
        """
        Get information about a specific process.

        Args:
            process_id: Process identifier

        Returns:
            Dictionary with process information or None if not found
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT * FROM processes WHERE process_id = ?
                """,
                (process_id,),
            )
            row = cursor.fetchone()

            if row:
                return dict(row)
            return None

    def get_process_logs(self, process_id: str) -> Optional[dict]:
        """
        Get log file paths for a process.

        Args:
            process_id: Process identifier

        Returns:
            Dictionary with log file paths:
            {
                'combined': str,  # Always present
                'stdout': Optional[str],
                'stderr': Optional[str],
                'has_separate_streams': bool
            }
        """
        process = self.get_process(process_id)
        if not process:
            return None

        return {
            "combined": process["log_file"],
            "stdout": process.get("stdout_log"),
            "stderr": process.get("stderr_log"),
            "has_separate_streams": process.get("has_separate_streams", False),
        }

    def list_processes(
        self,
        status: Optional[str] = None,
        limit: Optional[int] = None,
        with_separate_streams: Optional[bool] = None,
    ) -> list[dict]:
        """
        List all processes, optionally filtered by status and stream type.

        Args:
            status: Optional status filter ('running', 'completed', 'failed')
            limit: Maximum number of results to return
            with_separate_streams: Filter by whether process has separate stream logs

        Returns:
            List of process dictionaries, ordered by start time (newest first)
        """
        with self._get_connection() as conn:
            conditions = []
            params = []

            if status:
                conditions.append("status = ?")
                params.append(status)

            if with_separate_streams is not None:
                conditions.append("has_separate_streams = ?")
                params.append(1 if with_separate_streams else 0)

            if conditions:
                query = f"""
                    SELECT * FROM processes
                    WHERE {' AND '.join(conditions)}
                    ORDER BY started_at DESC
                """
            else:
                query = """
                    SELECT * FROM processes
                    ORDER BY started_at DESC
                """

            if limit:
                query += " LIMIT ?"
                params.append(limit)

            cursor = conn.execute(query, params)
            return [dict(row) for row in cursor.fetchall()]

    def delete_process(self, process_id: str) -> bool:
        """
        Delete a process from the registry.

        Args:
            process_id: Process identifier

        Returns:
            True if process was deleted, False if not found
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                DELETE FROM processes WHERE process_id = ?
                """,
                (process_id,),
            )
            conn.commit()
            return cursor.rowcount > 0

    def cleanup_old_processes(self, days: int = 7) -> int:
        """
        Remove completed/failed processes older than specified days.

        Args:
            days: Number of days to keep completed processes

        Returns:
            Number of processes deleted
        """
        cutoff = datetime.now().timestamp() - (days * 86400)
        cutoff_iso = datetime.fromtimestamp(cutoff).isoformat()

        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                DELETE FROM processes
                WHERE status IN ('completed', 'failed')
                AND completed_at < ?
                """,
                (cutoff_iso,),
            )
            conn.commit()
            return cursor.rowcount


# Maintain backward compatibility
if __name__ == "__main__":
    # Quick test
    registry = ProcessRegistry()
    print("ProcessRegistry v2 initialized successfully")
    print(f"Database: {registry.db_path}")

    # Test listing processes
    processes = registry.list_processes(limit=5)
    print(f"Found {len(processes)} recent processes")

    for p in processes:
        print(f"  - {p['process_id']}: {p['status']}")
        if p.get("has_separate_streams"):
            print(f"    Has separate stdout/stderr logs")
