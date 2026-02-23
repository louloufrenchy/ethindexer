import sys

# Block debugpy from ever loading
sys.modules["debugpy"] = None
