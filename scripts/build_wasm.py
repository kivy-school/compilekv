#!/usr/bin/env python3
"""Build the CompileKvWasm Swift package into a WASI reactor module.

Used by setup.py, and runnable on its own. Overrides: COMPILEKV_SWIFT,
COMPILEKV_WASM_SDK, COMPILEKV_SKIP_WASM_BUILD.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT_PACKAGE_DIR = ROOT / "CompileKvWasm"
PRODUCT_NAME = "CompileKvWasm"
DEFAULT_OUTPUT = ROOT / "src" / "compilekv" / "compilekv.wasm"
BUILT_MODULE = (
    SWIFT_PACKAGE_DIR / ".build" / "wasm32-unknown-wasip1" / "release" / f"{PRODUCT_NAME}.wasm"
)

# Reactor model, no debug info, size-optimized.
BUILD_FLAGS = [
    "-c",
    "release",
    "-Xswiftc",
    "-Xclang-linker",
    "-Xswiftc",
    "-mexec-model=reactor",
    "-Xswiftc",
    "-gnone",
    "-Xswiftc",
    "-Osize",
    "-Xlinker",
    "--strip-all",
]

VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")


class WasmBuildError(RuntimeError):
    pass


def _run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def _toolchain_version(swift: str) -> str | None:
    result = _run([swift, "--version"])
    match = VERSION_RE.search(result.stdout or "")
    return match.group(1) if match else None


def _available_sdks(swift: str) -> list[str]:
    result = _run([swift, "sdk", "list"])
    return [
        line.strip()
        for line in (result.stdout or "").splitlines()
        if line.strip().endswith("_wasm")
    ]


def _swiftly_toolchains() -> set[str]:
    if shutil.which("swiftly") is None:
        return set()
    result = _run(["swiftly", "list"])
    return set(VERSION_RE.findall(result.stdout or ""))


def resolve_build_command(swift: str) -> tuple[list[str], str]:
    """Pick a swift invocation and SDK whose versions match.

    An SDK only works with its own toolchain, so fall back to swiftly when the
    default one is a different version.
    """
    sdks = _available_sdks(swift)
    if not sdks:
        raise WasmBuildError(
            "No wasm Swift SDK installed. Install one with:\n"
            "  swift sdk install <swift-wasm-sdk-url>\n"
            "See https://www.swift.org/documentation/articles/wasm-getting-started.html"
        )

    requested = os.environ.get("COMPILEKV_WASM_SDK")
    if requested:
        if requested not in sdks:
            raise WasmBuildError(f"Swift SDK {requested!r} not found. Available: {sdks}")
        sdks = [requested]

    toolchain = _toolchain_version(swift)
    for sdk in sdks:
        match = VERSION_RE.search(sdk)
        if match and match.group(1) == toolchain:
            return [swift], sdk

    installed = _swiftly_toolchains()
    for sdk in sdks:
        match = VERSION_RE.search(sdk)
        if match and match.group(1) in installed:
            return ["swiftly", "run", f"+{match.group(1)}", swift], sdk

    raise WasmBuildError(
        f"Swift toolchain {toolchain} does not match any installed wasm SDK ({sdks}). "
        "Install the matching toolchain, or set COMPILEKV_WASM_SDK."
    )


def build(output: Path = DEFAULT_OUTPUT, force: bool = False) -> Path:
    output = Path(output)

    if not force and os.environ.get("COMPILEKV_SKIP_WASM_BUILD"):
        if output.is_file():
            print(f"COMPILEKV_SKIP_WASM_BUILD set, reusing {output}")
            return output
        raise WasmBuildError(
            f"COMPILEKV_SKIP_WASM_BUILD is set but {output} does not exist."
        )

    swift = os.environ.get("COMPILEKV_SWIFT", "swift")
    if shutil.which(swift) is None:
        raise WasmBuildError(
            f"{swift!r} not found on PATH. A Swift toolchain is required to build "
            "the wasm module. See https://www.swift.org/install/"
        )

    prefix, sdk = resolve_build_command(swift)
    command = [*prefix, "build", "--swift-sdk", sdk, *BUILD_FLAGS]
    print(f"Building wasm module: {' '.join(command)}", flush=True)

    result = subprocess.run(command, cwd=SWIFT_PACKAGE_DIR)
    if result.returncode != 0:
        raise WasmBuildError(f"swift build failed with exit code {result.returncode}")
    if not BUILT_MODULE.is_file():
        raise WasmBuildError(f"expected {BUILT_MODULE} to exist after a successful build")

    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(BUILT_MODULE, output)
    print(f"Wrote {output} ({output.stat().st_size / 1e6:.1f} MB)")
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Destination .wasm path.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Build even when COMPILEKV_SKIP_WASM_BUILD is set.",
    )
    args = parser.parse_args(argv)
    try:
        build(Path(args.output), force=args.force)
    except WasmBuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
