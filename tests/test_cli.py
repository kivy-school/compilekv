"""Tests for the compilekv command line interface."""

import pytest

from compilekv import main

from conftest import SIMPLE_KV


def test_compiles_a_directory(project, capsys):
    assert main([str(project)]) == 0

    assert (project / "simple.py").is_file()
    assert (project / "nested" / "canvas.py").is_file()
    assert "simple.kv" in capsys.readouterr().out


def test_defaults_to_the_current_directory(project, monkeypatch):
    monkeypatch.chdir(project)
    assert main([]) == 0
    assert (project / "simple.py").is_file()


def test_no_recursive_skips_subdirectories(project):
    assert main([str(project), "--no-recursive"]) == 0

    assert (project / "simple.py").is_file()
    assert not (project / "nested" / "canvas.py").exists()


def test_quiet_prints_nothing_on_success(project, capsys):
    assert main([str(project), "--quiet"]) == 0
    assert capsys.readouterr().out == ""


def test_output_flag_targets_a_single_file(tmp_path):
    kv = tmp_path / "simple.kv"
    kv.write_text(SIMPLE_KV)
    target = tmp_path / "custom.py"

    assert main([str(kv), "-o", str(target)]) == 0
    assert "class MyButton(Button):" in target.read_text()


def test_output_flag_rejects_multiple_files(project, capsys):
    assert main([str(project), "-o", str(project / "out.py")]) == 1
    assert "exactly one KV file" in capsys.readouterr().err


def test_missing_path_is_an_error(tmp_path, capsys):
    assert main([str(tmp_path / "absent")]) == 1
    assert "does not exist" in capsys.readouterr().err


def test_directory_without_kv_files_is_an_error(tmp_path, capsys):
    assert main([str(tmp_path)]) == 1
    assert "No .kv files found" in capsys.readouterr().err


def test_broken_kv_reports_and_exits_nonzero(tmp_path, capsys):
    (tmp_path / "bad.kv").write_text("<Broken\n    bad ::: syntax\n")

    assert main([str(tmp_path)]) == 1
    assert "bad.kv" in capsys.readouterr().err


def test_one_bad_file_does_not_stop_the_others(tmp_path, capsys):
    (tmp_path / "good.kv").write_text(SIMPLE_KV)
    (tmp_path / "bad.kv").write_text("<Broken\n    bad ::: syntax\n")

    assert main([str(tmp_path)]) == 1
    assert (tmp_path / "good.py").is_file()
    assert "bad.kv" in capsys.readouterr().err
