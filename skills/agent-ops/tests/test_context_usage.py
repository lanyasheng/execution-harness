"""Tests for context-usage.sh script."""

import os
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"


def run_context_usage(transcript_content):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        f.write(transcript_content)
        f.flush()
        result = subprocess.run(
            ["bash", str(SCRIPTS_DIR / "context-usage.sh"), f.name],
            capture_output=True, text=True, timeout=10,
        )
        os.unlink(f.name)
        return result.stdout.strip()


class TestContextUsage:
    def test_extracts_usage(self):
        # Create a fake transcript with >4KB of padding + token info at the end
        padding = '{"type":"message","content":"x"}\n' * 200  # ~6KB
        tail = '{"type":"response","input_tokens":80000,"context_window":200000}\n'
        output = run_context_usage(padding + tail)
        assert "Context usage:" in output
        assert "40%" in output  # 80000/200000 = 40%

    def test_empty_file_no_output(self):
        output = run_context_usage("")
        assert output == ""

    def test_small_file_no_output(self):
        output = run_context_usage('{"small": true}\n')
        assert output == ""

    def test_no_token_info_no_output(self):
        padding = '{"type":"message","content":"x"}\n' * 200
        output = run_context_usage(padding)
        assert output == ""
