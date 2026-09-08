"""Smoke test for `python -m compilekv`. The library is covered elsewhere."""

import subprocess
import sys


def test_runs_as_a_module(project):
    result = subprocess.run(
        [sys.executable, "-m", "compilekv", str(project)],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert (project / "simple.py").is_file()


def test_a_directory_in_means_a_directory_out(project):
    out = project / "build"
    result = subprocess.run(
        [sys.executable, "-m", "compilekv", str(project), "-o", str(out)],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert (out / "simple.py").is_file()
    assert not (project / "simple.py").exists()
