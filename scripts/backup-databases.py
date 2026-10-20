"""Prepare checked logical database backups before btrbk takes snapshots."""

from contextlib import closing
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def backup_sqlite(source, destination):
    # The backup API includes committed WAL data while the application runs.
    with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True)) as live:
        with closing(sqlite3.connect(destination)) as backup:
            live.backup(backup, pages=128)
            if backup.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise RuntimeError(f"SQLite integrity check failed: {source}")


def main():
    os.umask(0o077)
    destination = Path("/var/lib/oggy-database-backups")
    # Keep the previous checked dumps until every new dump has passed validation.
    with tempfile.TemporaryDirectory(prefix=".pending-", dir=destination) as pending:
        pending = Path(pending)
        backup_sqlite(
            Path("/home/killeik/selfhost/forgejo/gitea/gitea.db"),
            pending / "forgejo.sqlite",
        )
        backup_sqlite(
            Path("/var/lib/grafana/data/grafana.db"), pending / "grafana.sqlite"
        )
        with (pending / "miniflux.dump").open("wb") as dump:
            subprocess.run(
                [
                    "docker", "exec", "miniflux-db", "pg_dump",
                    "-U", "miniflux", "-d", "miniflux", "-Fc",
                ],
                stdout=dump,
                check=True,
            )
        with (pending / "miniflux.dump").open("rb") as dump:
            subprocess.run(
                ["docker", "exec", "-i", "miniflux-db", "pg_restore", "--list"],
                stdin=dump,
                stdout=subprocess.DEVNULL,
                check=True,
            )
        for name in ("forgejo.sqlite", "grafana.sqlite", "miniflux.dump"):
            os.replace(pending / name, destination / name)


if __name__ == "__main__":
    main()
