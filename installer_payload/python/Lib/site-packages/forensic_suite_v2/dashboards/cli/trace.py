import argparse
import asyncio

from forensic_suite_v2.dashboards.data import DashboardDataService, TraceQuery


async def run(address: str, chain: str | None, limit: int) -> None:
    service = DashboardDataService()
    await service.connect()
    try:
        rows = await service.trace(TraceQuery(address=address, chain=chain, limit=limit))
        print(f"Rows: {len(rows)}")
        for row in rows:
            print(
                f"{row.chain.upper():<5} | {row.ts} | block={row.block_number} | "
                f"{row.direction:<3} | tx={row.txid} | contract={row.contract_address or '-'} | amount={row.amount_raw or '-'}"
            )
    finally:
        await service.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", required=True)
    parser.add_argument("--chain", default=None)
    parser.add_argument("--limit", type=int, default=250)
    args = parser.parse_args()
    asyncio.run(run(args.address, args.chain, args.limit))


if __name__ == "__main__":
    main()
