"""Real-Postgres support for tests that depend on row locks.

SQLite ignores ``FOR UPDATE``, so lock behaviour can only be tested on Postgres.

Server selection:
- ``TEST_POSTGRES_URL``: use that server (asyncpg URL). Tests only ever touch a
  uniquely named throwaway schema, never existing tables.
- otherwise: start a temporary local cluster if ``initdb`` is available.
- otherwise: skip, or fail if ``REQUIRE_POSTGRES_TESTS=1`` (set this in CI so the
  race tests cannot silently stop running).
"""
from __future__ import annotations

import glob
import os
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

import pytest


def _find_pg_binary(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    candidates = sorted(glob.glob(f"/usr/lib/postgresql/*/bin/{name}"))
    return candidates[-1] if candidates else None


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _unavailable(reason: str) -> None:
    if os.environ.get("REQUIRE_POSTGRES_TESTS") == "1":
        pytest.fail(f"Postgres tests are required but cannot run: {reason}")
    pytest.skip(f"Postgres unavailable: {reason}")


@pytest.fixture(scope="session")
def postgres_url():
    configured = os.environ.get("TEST_POSTGRES_URL", "").strip()
    if configured:
        yield configured
        return

    initdb, pg_ctl = _find_pg_binary("initdb"), _find_pg_binary("pg_ctl")
    if not initdb or not pg_ctl:
        _unavailable("set TEST_POSTGRES_URL or install Postgres server binaries")

    base = Path(tempfile.mkdtemp(prefix="yoma-pg-"))
    data_dir, port = base / "data", _free_port()
    try:
        subprocess.run(
            [initdb, "-D", str(data_dir), "-U", "postgres", "--auth=trust", "-E", "UTF8"],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                pg_ctl, "-D", str(data_dir), "-w", "-l", str(base / "log"),
                "-o", f"-p {port} -k {base} -c listen_addresses=127.0.0.1 -c fsync=off",
                "start",
            ],
            check=True,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        shutil.rmtree(base, ignore_errors=True)
        _unavailable(f"could not start a temporary cluster: {exc}")

    try:
        yield f"postgresql+asyncpg://postgres@127.0.0.1:{port}/postgres"
    finally:
        subprocess.run(
            [pg_ctl, "-D", str(data_dir), "-m", "immediate", "stop"],
            check=False,
            capture_output=True,
        )
        shutil.rmtree(base, ignore_errors=True)
