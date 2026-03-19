```mermaid
flowchart TD

    A[Repo A - Control Host<br>Build + Deploy Orchestrator] --> B(Deploy-Cluster.ps1)

    B --> C[192.168.0.172<br>BTC Ingestion Host]
    B --> D[192.168.0.165<br>TRON Ingestion Host]
    B --> E[192.168.0.199<br>ETH Ingestion Host]

    C --> C1[indexer.yaml (btc)]
    D --> D1[indexer.yaml (tron)]
    E --> E1[indexer.yaml (eth)]

    C1 --> C2[Restart Orchestrator]
    D1 --> D2[Restart Orchestrator]
    E1 --> E2[Restart Orchestrator]

    C2 --> F[(Postgres 192.168.0.28)]
    D2 --> F
    E2 --> F
```
