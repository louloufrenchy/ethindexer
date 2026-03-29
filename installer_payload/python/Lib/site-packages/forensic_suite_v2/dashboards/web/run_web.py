import subprocess
import sys

if __name__ == "__main__":
    try:
        import uvicorn
    except ImportError:
        print("[INFO] Installing uvicorn...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "uvicorn[standard]"])
        import uvicorn

    uvicorn.run(
        "forensic_suite_v2.dashboards.web.app:app",
        host="127.0.0.1",
        port=8000,
        reload=False
    )
