"""Tests for Ralph persistent execution loop scripts."""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"


@pytest.fixture
def ralph_env(tmp_path):
    """Create isolated ralph state directories."""
    ralph_dir = tmp_path / "ralph"
    cancel_dir = tmp_path / "cancel"
    ralph_dir.mkdir()
    cancel_dir.mkdir()
    env = os.environ.copy()
    env["HOME"] = str(tmp_path)
    # Create the expected directory structure
    shared = tmp_path / ".openclaw" / "shared-context"
    (shared / "ralph").mkdir(parents=True)
    (shared / "cancel").mkdir(parents=True)
    return env, tmp_path


def run_script(script_name, env, stdin_data="", args=None):
    """Run a bash script and return (stdout, returncode)."""
    cmd = ["bash", str(SCRIPTS_DIR / script_name)]
    if args:
        cmd.extend(args)
    result = subprocess.run(
        cmd, capture_output=True, text=True, env=env,
        input=stdin_data, timeout=10,
    )
    return result.stdout.strip(), result.returncode


class TestRalphInit:
    def test_creates_state_file(self, ralph_env):
        env, tmp = ralph_env
        stdout, rc = run_script("ralph-init.sh", env, args=["test-sess", "20"])
        assert rc == 0
        state_file = tmp / ".openclaw/shared-context/ralph/test-sess.json"
        assert state_file.exists()
        state = json.loads(state_file.read_text())
        assert state["session_id"] == "test-sess"
        assert state["active"] is True
        assert state["iteration"] == 0
        assert state["max_iterations"] == 20

    def test_default_max_iterations(self, ralph_env):
        env, tmp = ralph_env
        run_script("ralph-init.sh", env, args=["test-sess"])
        state_file = tmp / ".openclaw/shared-context/ralph/test-sess.json"
        state = json.loads(state_file.read_text())
        assert state["max_iterations"] == 50

    def test_missing_session_id_fails(self, ralph_env):
        env, _ = ralph_env
        _, rc = run_script("ralph-init.sh", env, args=[])
        assert rc != 0


class TestRalphStopHook:
    def test_allows_when_no_session(self, ralph_env):
        env, _ = ralph_env
        # No NC_SESSION set
        env.pop("NC_SESSION", None)
        stdout, rc = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        assert rc == 0
        result = json.loads(stdout)
        assert result.get("continue") is True

    def test_allows_when_no_state_file(self, ralph_env):
        env, _ = ralph_env
        env["NC_SESSION"] = "nonexistent-session"
        stdout, rc = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        assert rc == 0
        result = json.loads(stdout)
        assert result.get("continue") is True

    def test_blocks_when_active(self, ralph_env):
        env, tmp = ralph_env
        # Init ralph state
        run_script("ralph-init.sh", env, args=["block-test", "10"])
        env["NC_SESSION"] = "block-test"
        stdout, rc = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        assert rc == 0
        result = json.loads(stdout)
        assert result.get("decision") == "block"
        assert "RALPH LOOP 1/10" in result.get("reason", "")

    def test_increments_iteration(self, ralph_env):
        env, tmp = ralph_env
        run_script("ralph-init.sh", env, args=["inc-test", "10"])
        env["NC_SESSION"] = "inc-test"
        # Block twice
        run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        stdout, _ = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        result = json.loads(stdout)
        assert "RALPH LOOP 2/10" in result.get("reason", "")

    def test_allows_after_max_iterations(self, ralph_env):
        env, tmp = ralph_env
        run_script("ralph-init.sh", env, args=["max-test", "3"])
        env["NC_SESSION"] = "max-test"
        # Exhaust 3 iterations
        for _ in range(3):
            run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        # 4th should allow
        stdout, _ = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        result = json.loads(stdout)
        assert result.get("continue") is True

    def test_allows_when_inactive(self, ralph_env):
        env, tmp = ralph_env
        run_script("ralph-init.sh", env, args=["inactive-test", "10"])
        # Manually set inactive
        state_file = tmp / ".openclaw/shared-context/ralph/inactive-test.json"
        state = json.loads(state_file.read_text())
        state["active"] = False
        state_file.write_text(json.dumps(state))
        env["NC_SESSION"] = "inactive-test"
        stdout, _ = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        result = json.loads(stdout)
        assert result.get("continue") is True


class TestRalphCancel:
    def test_creates_cancel_signal(self, ralph_env):
        env, tmp = ralph_env
        stdout, rc = run_script("ralph-cancel.sh", env, args=["cancel-test"])
        assert rc == 0
        cancel_file = tmp / ".openclaw/shared-context/cancel/cancel-test.json"
        assert cancel_file.exists()
        signal = json.loads(cancel_file.read_text())
        assert "requested_at" in signal
        assert "expires_at" in signal
        assert signal["reason"] == "user_abort"

    def test_custom_reason(self, ralph_env):
        env, tmp = ralph_env
        run_script("ralph-cancel.sh", env, args=["cancel-test", "timeout"])
        cancel_file = tmp / ".openclaw/shared-context/cancel/cancel-test.json"
        signal = json.loads(cancel_file.read_text())
        assert signal["reason"] == "timeout"

    def test_cancel_stops_ralph(self, ralph_env):
        env, tmp = ralph_env
        run_script("ralph-init.sh", env, args=["cancel-flow", "50"])
        run_script("ralph-cancel.sh", env, args=["cancel-flow"])
        env["NC_SESSION"] = "cancel-flow"
        stdout, _ = run_script("ralph-stop-hook.sh", env, stdin_data="{}")
        result = json.loads(stdout)
        assert result.get("continue") is True
        # Check state shows cancelled
        state_file = tmp / ".openclaw/shared-context/ralph/cancel-flow.json"
        state = json.loads(state_file.read_text())
        assert state["active"] is False
        assert state["deactivation_reason"] == "cancelled"
