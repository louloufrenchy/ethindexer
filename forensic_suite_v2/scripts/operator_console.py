import cmd
import subprocess
import json
from pathlib import Path
from forensic_suite_v2.scripts.healthcheck import run_healthcheck
from forensic_suite_v2.scripts.operator_console import OperatorConsole

MANIFEST_PATH = Path("chains.json")


def load_manifest():
    with open(MANIFEST_PATH) as f:
        return json.load(f)["chains"]


class OperatorConsole(cmd.Cmd):
    intro = "Forensic Suite Operator Console. Type help or ? to list commands.\n"
    prompt = "(forensic) "

    def __init__(self):
        super().__init__()
        self.chains = load_manifest()

    def do_list_chains(self, arg):
        """List all chains and their enabled status."""
        for name, cfg in self.chains.items():
            status = "ENABLED" if cfg.get("enabled", False) else "DISABLED"
            print(f"{name}: {status}")

    def do_enable(self, chain):
        """Enable a chain: enable tron"""
        if chain in self.chains:
            self.chains[chain]["enabled"] = True
            self._save_manifest()
            print(f"{chain} enabled")
        else:
            print(f"Unknown chain: {chain}")

    def do_disable(self, chain):
        """Disable a chain: disable tron"""
        if chain in self.chains:
            self.chains[chain]["enabled"] = False
            self._save_manifest()
            print(f"{chain} disabled")
        else:
            print(f"Unknown chain: {chain}")

    def do_start_all(self, arg):
        """Start all enabled indexers."""
        subprocess.Popen(["python", "scripts/start_all_indexers.py"])

    def do_health(self, arg):
        """Run healthcheck for all enabled chains."""
        subprocess.Popen(["python", "scripts/healthcheck.py"])

    def do_show_manifest(self, arg):
        """Show current chain manifest."""
        print(json.dumps({"chains": self.chains}, indent=2))

    def do_exit(self, arg):
        """Exit the console."""
        print("Exiting operator console.")
        return True

    def _save_manifest(self):
        with open(MANIFEST_PATH, "w") as f:
            json.dump({"chains": self.chains}, f, indent=2)


if __name__ == "__main__":
    OperatorConsole().cmdloop()
