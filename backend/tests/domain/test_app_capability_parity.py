import json
from pathlib import Path

from niimstudio.domain.printer_capabilities import (
    PrintOrientation,
    get_printer_capabilities,
    printable_bounds_px,
)


def test_d11_app_contract_matches_authoritative_capabilities():
    contract_path = (
        Path(__file__).resolve().parents[3] / "app" / "assets" / "contracts" / "d11_preview_capabilities.v1.json"
    )
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    printer = get_printer_capabilities("d11")
    label = printer.labels[0]
    bounds = printable_bounds_px(printer, label, PrintOrientation.NORMAL)

    assert contract == {
        "schema_version": 1,
        "model_id": printer.model_id,
        "model_name": printer.display_name,
        "dpi_x": printer.dpi_x,
        "dpi_y": printer.dpi_y,
        "label_id": label.label_id,
        "label_name": label.display_name,
        "media_width_mm": str(label.media_width_mm),
        "media_length_mm": str(label.media_length_mm),
        "native_width_px": bounds.width_px,
        "native_length_px": bounds.height_px,
    }
