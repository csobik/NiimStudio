# Copilot Instructions

Read `AGENTS.md` and the local documents it references before making changes.
Those files are authoritative.

The current repository contains a standalone Python console application and
printer core. It does not contain the historical Tkinter UI. Legacy GUI code is
available only on the non-merge branch `legacy/tkinter-app` for reference.

Use Poetry for setup and verification:

```bash
poetry install
poetry check
poetry run python -m compileall -q NiimPrintX
poetry run ruff check NiimPrintX tests
poetry run ruff format --check NiimPrintX tests
poetry run pytest
```

Normal tests never discover or connect to real Bluetooth devices. Use fake
devices and transports for CLI, BLE, protocol, and raster behavior.
