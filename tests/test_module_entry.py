"""One smoke test for `python -m compilekv`.

The command line is a thin wrapper over the library, which is what the rest of
the suite covers. This only checks the wrapper is wired up.
"""

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
