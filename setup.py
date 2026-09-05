"""Build hook: compile the Swift package to wasm and ship it as package data."""

from __future__ import annotations

import sys
from pathlib import Path

from setuptools import Command, setup
from setuptools.command.build import build as _build
from setuptools.command.build_py import build_py as _build_py

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))

import build_wasm  # noqa: E402


class build_wasm_command(Command):
    description = "Build the CompileKvWasm module and place it in the package."
    user_options = [("force", "f", "Build even when COMPILEKV_SKIP_WASM_BUILD is set.")]
    boolean_options = ["force"]

    def initialize_options(self) -> None:
        self.force = False

    def finalize_options(self) -> None:
        pass

    def run(self) -> None:
        build_wasm.build(build_wasm.DEFAULT_OUTPUT, force=bool(self.force))


class build(_build):
    # The module must exist before anything collects package data.
    sub_commands = [("build_wasm", None), *_build.sub_commands]


class build_py(_build_py):
    def run(self) -> None:
        self.run_command("build_wasm")
        super().run()


setup(
    cmdclass={
        "build": build,
        "build_py": build_py,
        "build_wasm": build_wasm_command,
    }
)
