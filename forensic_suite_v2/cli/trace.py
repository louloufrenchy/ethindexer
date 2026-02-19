# forensic_suite_v2/cli/trace.py
import argparse, asyncio, os
from datetime import datetime
from dotenv import load_dotenv
from forensic_suite_v2.tracer_engine.manifest_v2 import TraceSeed, TraceManifestV2
from forensic_suite_v2.tracer_engine.multi_chain_tracer_v2 import run_multi_chain_trace_v2
from forensic_suite_v2.tracer_engine.multi_chain_recursive_v2 import run_traces_v2_multi_chain
from forensic_suite_v2.cli.__main__ import cli

load_dotenv()

def build_manifest(name, seed):
    return TraceManifestV2(
        name=name,
        created_at=datetime.utcnow().isoformat(),
        seeds=[seed],
        options={"retry": 3, "timeout": 30},
    )

def cmd_trace_address(args):
    seed = TraceSeed(chain=args.chain, kind="address", value=args.address,
                     max_depth=args.max_depth, max_branches=args.max_branches)
    manifest = build_manifest(f"{args.chain}_addr_{args.address[:8]}", seed)
    asyncio.run(run_multi_chain_trace_v2(manifest, output_root=args.output, debug=True))

def cmd_trace_tx(args):
    seed = TraceSeed(chain=args.chain, kind="tx", value=args.txid,
                     max_depth=args.max_depth, max_branches=args.max_branches)
    manifest = build_manifest(f"{args.chain}_tx_{args.txid[:8]}", seed)
    asyncio.run(run_multi_chain_trace_v2(manifest, output_root=args.output, debug=True))

def cmd_trace_utxo(args):
    seed = TraceSeed(chain="btc", kind="utxo", value=args.utxo,
                     max_depth=args.max_depth, max_branches=args.max_branches)
    manifest = build_manifest(f"btc_utxo_{args.utxo}", seed)
    asyncio.run(run_multi_chain_trace_v2(manifest, output_root=args.output, debug=True))

def cmd_multi_chain(args):
    asyncio.run(run_traces_v2_multi_chain(
        input_path=args.input,
        output_root=args.output,
        max_depth=args.max_depth,
        max_branches=args.max_branches,
        recursive=True,
        debug=True,
    ))

def main():
    parser = argparse.ArgumentParser(prog="forensic-suite-v2-trace")
    sub = parser.add_subparsers(dest="cmd", required=True)

    for cmd, args in {
        "trace-address": [("--chain", True), ("--address", True)],
        "trace-tx": [("--chain", True), ("--txid", True)],
        "trace-utxo": [("--utxo", True)],
        "multi-chain": [("--input", True)],
    }.items():
        p = sub.add_parser(cmd)
        for arg, required in args:
            p.add_argument(arg, required=required)
        p.add_argument("--max-depth", type=int, default=3)
        p.add_argument("--max-branches", type=int, default=20)
        p.add_argument("--output", default="output")
        p.set_defaults(func=globals()[f"cmd_{cmd.replace('-', '_')}"])

    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
