✅ 4. Migration Checklist for Upgraded Dashboard
This is the operational hygiene piece — the part you always nail.

🔧 PREPARE
[ ] Create branch: feature/plugin-system-tightening

[ ] Apply updated plugin loader

[ ] Add plugin template

[ ] Add CI validator script

[ ] Add unit tests under tests/

[ ] Ensure all existing plugins define Plugin class

🧪 TEST LOCALLY
[ ] Run cockpit locally: python -m forensic_suite_v2.gui

[ ] Confirm tracer dropdown populates

[ ] Confirm chain filtering works

[ ] Confirm dashboards launch

[ ] Run unit tests: pytest -q

[ ] Run validator: python tools/validate_plugins.py

📦 BUILD
[ ] Bump version in __init__.py

[ ] Build wheel: python -m build

[ ] Inspect wheel contents for plugin folder

🚀 DEPLOY
[ ] Deploy to one host (blue slot)

[ ] Validate cockpit

[ ] Validate dashboards

[ ] Validate tracer

[ ] Validate logs

🔁 PROMOTE
[ ] Switch traffic to blue

[ ] Deploy to remaining hosts

[ ] Merge branch into dev

[ ] Tag release