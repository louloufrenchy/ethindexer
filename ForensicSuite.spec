# -*- mode: python ; coding: utf-8 -*-
import os

project_root = os.path.abspath(SPECPATH)

# Helper to build the list of (destination, source, 'DATA')
def get_data_files(folder_name):
    src_path = os.path.join(project_root, folder_name)
    data_list = []
    if not os.path.exists(src_path):
        return data_list
    for root, dirs, files in os.walk(src_path):
        for file in files:
            full_path = os.path.join(root, file)
            # This is the destination relative to the EXE root
            rel_path = os.path.relpath(full_path, project_root)
            data_list.append((rel_path, full_path, 'DATA'))
    return data_list

# 1. Prepare custom data
all_custom_data = []
all_custom_data.extend(get_data_files('forensic_suite_v2'))
all_custom_data.extend(get_data_files('dashboards'))
all_custom_data.extend(get_data_files('scripts'))

a = Analysis(
    ['forensic_suite_v2\\gui\\app.py'],
    pathex=[project_root],
    binaries=[],
    datas=[], 
    hiddenimports=[],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='ForensicSuite',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    icon=os.path.join(project_root, 'forensic_suite_v2', 'gui', 'icons', 'forensic.ico') if os.path.exists(os.path.join(project_root, 'forensic_suite_v2', 'gui', 'icons', 'forensic.ico')) else None
)

# 2. THE CRITICAL FIX: Merge TOCs manually into a flat list
# This prevents the "too many values to unpack" error by ensuring 
# every single item is a 3-part tuple before COLLECT sees it.
final_toc = []
for item in a.binaries:
    final_toc.append(item)
for item in a.datas:
    final_toc.append(item)
for item in all_custom_data:
    final_toc.append(item)

coll = COLLECT(
    exe,
    final_toc, # Pass as ONE list, no splat (*) operator
    strip=False,
    upx=True,
    upx_exclude=[],
    name='ForensicSuite',
)