---
name: convert-pdf-to-md
description: 'Use when the user shares, references, or asks to read, summarize, review, extract data from, compare, or analyze a .pdf file — a report, paper, invoice, form, contract, or scanned document — even if they don''t say "convert" or "markdown". Also use for batch requests over a folder of PDFs, and alongside convert-word-to-md / convert-excel-to-md when a folder mixes .pdf with .docx or .xlsx so no file type is skipped.'
---

# Convert PDF to Markdown

## When to use this skill

Trigger this skill any time there is a `.pdf` file that needs to be
understood or processed — for example, a user attaches a PDF and asks
questions about it, wants a summary, wants specific data or tables pulled
out, or wants multiple PDFs in a folder processed together. PDF is a
layout/print format, not reliably readable as plain text, so always convert
it to Markdown first using the script in this skill.

**Do not call the Read tool (or any other file-reading method) on the
`.pdf` file directly** — even to "quickly check" or "skim" it. Claude
Code's Read tool can technically open PDFs, which is exactly why this rule
is easy to miss: it doesn't feel like "parsing" or "ad-hoc code," it feels
like using a normal tool. The `.pdf` path is only a valid argument to the
conversion script below.

**Common mistake:** skimming the PDF with Read because "it seems to
work" — Read's rendering skips embedded images and loses table structure,
defeating the point of this skill.

**This still applies under time pressure.** "Quickly," "just skim it,"
"don't worry about any formal process" are not exceptions — the script
takes a second or two to run. Skipping it to save time is the mistake this
rule exists to prevent, not a reasonable judgment call.

This skill only supports `.pdf` — that's MarkItDown's only PDF-family
format, so there's no legacy format to worry about here (unlike Word's
`.doc` or Excel's `.xls`).

**Mixed file types:** When the user references a folder or set of documents
containing multiple supported file types (`.pdf`, `.docx`, `.xlsx`), this
skill handles only `.pdf` files. The agent MUST also invoke the sibling
skills in parallel:
- `convert-word-to-md` for any `.docx` files
- `convert-excel-to-md` for any `.xlsx` files

Never process a folder and silently skip a supported file type. All three
skills must be invoked together when mixed types are present.

## Setup (once per environment)

Before the first conversion in a given environment, follow
[`references/setup.md`](references/setup.md) step by step to ensure Python,
pip, `markitdown`, and `pymupdf` (for image extraction) are installed. Do
this proactively rather than guessing whether the environment is ready — the
script itself will also fail with a clear pointer back to that file if a
dependency turns out to be missing, so it's safe to just try the conversion
first if you're reasonably confident setup was already done.

## Usage

The conversion script lives at `scripts/convert_pdf_to_md.py`.

**Output structure:** MarkItDown's PDF converter extracts text and tables
only — it has no concept of embedded images at all. This script separately
extracts real embedded images via PyMuPDF and writes a self-contained folder
per document:

```
<name>/
    img/
        page001_img001.<ext>
        page002_img001.<ext>
        ...
    <name>.md
```

Because MarkItDown's PDF text does not preserve reliable per-page markers,
there's no safe way to know exactly where inline an image belongs. Rather
than risk misplacing images next to the wrong paragraph, the script appends
a `## Extracted Images` section at the end of the Markdown, with a
`### Page N` subheading per page that has images — read this section
separately from the main body text. If the document has no embedded images,
no `img/` folder or `Extracted Images` section is created.

**Single file:**

```powershell
python scripts\convert_pdf_to_md.py "C:\path\to\document.pdf"
```

This creates a `document\` folder next to the source file (containing
`document.md` and, if present, `document\img\`). To control the destination
folder explicitly:

```powershell
python scripts\convert_pdf_to_md.py "C:\path\to\document.pdf" -o "C:\path\to\output_folder"
```

**A folder of PDFs (batch mode):**

```powershell
python scripts\convert_pdf_to_md.py "C:\path\to\folder"
```

Add `--recursive` to also include subfolders:

```powershell
python scripts\convert_pdf_to_md.py "C:\path\to\folder" --recursive
```

Each `.pdf` found gets its own `<name>\` output folder next to it by
default. Pass `-o "C:\path\to\output_parent"` to collect all the generated
`<name>\` folders under a separate parent directory instead (subfolder
structure is preserved when combined with `--recursive`).

After conversion, read the resulting `.md` file(s) to perform the actual
analysis the user asked for — the script's job is only to produce accurate
Markdown (and images), not to interpret the content.

## Deciding where output goes

**Default — always output next to the source file.** The `<name>/` folder
is created in the same directory as the source `.pdf`. This is the required
default for every case. Do NOT override it unless the user explicitly asks
for a different location.

**Only use `-o` when** the user explicitly provides an output path (e.g.,
"save the output to `C:\output`", "put the results in `D:\work`"). Do NOT
pass `-o` based on the agent's current working directory, the session state
folder, or any implied location.

**If the source file path cannot be fully resolved** — for example, the
user provides only a filename with no directory, or the path is ambiguous —
use `ask_user` to confirm the full absolute path before running the
conversion. Never guess or assume the directory.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ModuleNotFoundError: No module named 'markitdown'` or `'fitz'` / exit code 2 | MarkItDown or PyMuPDF not installed | Follow `references/setup.md` |
| `ERROR: Unsupported file type '...'` / exit code 3 | Not a `.pdf` file | Ask the user for the correct file, or if it's `.doc`/`.docx`/`.xlsx`, use the matching sibling skill instead |
| `ERROR: Input path not found` / exit code 3 | Wrong path, or file moved | Confirm the correct path with the user |
| `FAILED <file> -> ...` in batch output | That specific file is corrupt, password-protected, or otherwise unreadable | Report which file(s) failed; other files in the batch still succeed |
| `NOTE: skipped N non-.pdf file(s)` | Folder contains non-PDF files | Expected — those files are intentionally ignored |
| Markdown body is empty or near-empty despite images being extracted | The PDF is scanned/image-only with no embedded text layer; MarkItDown does not perform OCR | Tell the user OCR isn't supported — the extracted page images are still available for them to view |
| Images appear in an appendix instead of inline with the text | Deliberate limitation — MarkItDown's PDF text has no reliable per-page markers to place images inline | Expected behavior; cross-reference the `### Page N` heading with the surrounding text context if needed |
