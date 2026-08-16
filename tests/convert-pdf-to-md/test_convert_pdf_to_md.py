import importlib.util
import subprocess
import sys
from pathlib import Path

SCRIPT_PATH = (
    Path(__file__).resolve().parents[2]
    / "plugins" / "convert-pdf-to-md" / "skills" / "convert-pdf-to-md"
    / "scripts" / "convert_pdf_to_md.py"
)


def _load_module():
    spec = importlib.util.spec_from_file_location("convert_pdf_to_md", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


convert_pdf_to_md = _load_module()


def test_find_pdf_files_non_recursive_skips_subdirs_and_non_pdf(tmp_path):
    (tmp_path / "a.pdf").write_text("x")
    (tmp_path / "b.PDF").write_text("x")
    (tmp_path / "c.txt").write_text("x")
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "d.pdf").write_text("x")

    pdf_files, skipped = convert_pdf_to_md.find_pdf_files(tmp_path, recursive=False)

    assert {p.name for p in pdf_files} == {"a.pdf", "b.PDF"}
    assert skipped == 1


def test_find_pdf_files_recursive_includes_subdirs(tmp_path):
    (tmp_path / "a.pdf").write_text("x")
    (tmp_path / "c.txt").write_text("x")
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "d.pdf").write_text("x")

    pdf_files, skipped = convert_pdf_to_md.find_pdf_files(tmp_path, recursive=True)

    assert {p.name for p in pdf_files} == {"a.pdf", "d.pdf"}
    assert skipped == 1


def test_build_image_appendix_empty():
    assert convert_pdf_to_md.build_image_appendix({}) == ""


def test_build_image_appendix_orders_pages_ascending():
    written_by_page = {
        2: ["page002_img001.png"],
        1: ["page001_img001.jpg"],
    }

    result = convert_pdf_to_md.build_image_appendix(written_by_page)

    expected = (
        "\n## Extracted Images\n"
        "\n### Page 1\n"
        "\n![page001_img001.jpg](img/page001_img001.jpg)\n"
        "\n### Page 2\n"
        "\n![page002_img001.png](img/page002_img001.png)\n"
    )
    assert result == expected


def test_cli_help_exits_zero_without_dependencies_installed():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "Path to a .pdf file" in result.stdout


def test_cli_missing_input_path_exits_three():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "/nonexistent/path/does-not-exist.pdf"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 3
    assert "Input path not found" in result.stderr


def test_cli_non_pdf_input_exits_three(tmp_path):
    txt_file = tmp_path / "notes.txt"
    txt_file.write_text("hello")

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(txt_file)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 3
    assert "Unsupported file type" in result.stderr
