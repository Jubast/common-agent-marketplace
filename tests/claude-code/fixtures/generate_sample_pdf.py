"""Write a minimal, valid, single-page PDF using raw PDF object syntax.

No third-party dependencies (no reportlab/fpdf) -- this exists purely so
tests don't need to commit a binary .pdf fixture to git.
"""
from pathlib import Path

SAMPLE_TEXT = "Sample Invoice for Acme Corp. Total: 42.00 USD"


def generate_sample_pdf(dest_path: Path, text: str = SAMPLE_TEXT) -> None:
    """Write a one-page PDF containing `text` to `dest_path`."""
    content_stream = f"BT /F1 24 Tf 72 712 Td ({text}) Tj ET"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> "
        "/MediaBox [0 0 612 792] /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        f"<< /Length {len(content_stream)} >>\nstream\n{content_stream}\nendstream",
    ]

    header = b"%PDF-1.4\n"
    body_parts = []
    offsets = [0]  # object 0 is the free-list head, offset unused
    offset = len(header)
    for i, obj in enumerate(objects, start=1):
        obj_bytes = f"{i} 0 obj\n{obj}\nendobj\n".encode("latin-1")
        offsets.append(offset)
        body_parts.append(obj_bytes)
        offset += len(obj_bytes)

    body = b"".join(body_parts)
    xref_offset = len(header) + len(body)

    xref_lines = [f"xref\n0 {len(objects) + 1}\n", "0000000000 65535 f \n"]
    for off in offsets[1:]:
        xref_lines.append(f"{off:010d} 00000 n \n")
    xref = "".join(xref_lines).encode("latin-1")

    trailer = (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n"
    ).encode("latin-1")

    dest_path.write_bytes(header + body + xref + trailer)


if __name__ == "__main__":
    import sys

    generate_sample_pdf(Path(sys.argv[1]))
