# LVR-Shielded LP Vault for Uniswap v4

A Uniswap v4 Hook + Vault that dynamically adjusts LP ranges to reduce Loss-Versus-Rebalancing (LVR) via automated risk modes and guardrails. Built for ETHGlobal NYC 2025.

## Table of Contents

* [Overview](#overview)
* [Live Deployment (Unichain Sepolia)](#live-deployment-unichain-sepolia)
* [How It Works](#how-it-works)
* [Repo Layout](#repo-layout)
* [Prerequisites](#prerequisites)
* [Quickstart (Local Graph + Demo)](#quickstart-local-graph--demo)
* [Environment](#environment)
* [Local Subgraph Stack](#local-subgraph-stack)
* [Demo Script: What It Does](#demo-script-what-it-does)
* [GraphQL Queries](#graphql-queries)
* [Events & Entity Schema](#events--entity-schema)
* [Signals vs Modes (How They Correlate)](#signals-vs-modes-how-they-correlate)
* [Contracts & Admin](#contracts--admin)
* [Testing & Gas](#testing--gas)
* [Troubleshooting](#troubleshooting)
* [Roadmap](#roadmap)
* [License](#license)

## Overview

The LVR-Shielded Vault monitors price and volatility, then switches **modes** that widen or tighten Uniswap v4 LP ranges:

* `NORMAL`: tight range (baseline)
* `WIDENED`: \~2× wider when volatility or deviation rises
* `RISK_OFF`: \~3×+ wider for maximum capital protection

A companion **subgraph** indexes Hook+Vault events for analytics and demos. The included `demo-e2e.sh` shows an end-to-end flow: start Graph node + IPFS, deploy the subgraph, send three on-chain demo txs (`RISK_OFF → WIDENED → NORMAL`), wait for indexing, and then query the exact results.

## Live Deployment (Unichain Sepolia)

* **Vault:** `0x84a4871295867f587B15EAFF82e80eA2EbA79a6C`
* **Hook:**  `0x20c519Cca0360468C0eCd7A74bEc12b9895C44c0`
* **Oracle (mock or Pyth-wired in future):** `0xf406Cf48630FFc810FCBF1454d8F680a36D1AF64`
* **Factory:** `0x45ad11A2855e010cd57C8C8eF6fb5A15e15C6b7A`

> Chain: **Unichain Sepolia** RPC you provide via `RPC_URL`.

## How It Works

* **Hook (Uniswap v4 BaseHook):** inspects price/volatility and proposes range changes.
* **Vault:** executes the placement and emits `ModeApplied` + telemetry events.
* **Signals:** the Hook also emits `Signal(spotTick, ewmaTick, sigmaTicks)` each “epoch” the demo sends, which the Vault uses (plus gates like dwell-time, hysteresis, confirmation count) to decide mode transitions.

## Repo Layout

```
.
├── contracts/               # Hook, Vault, supporting libs
├── script/                  # Deployment scripts
├── subgraph/                # The Graph manifest, mappings, docker-compose
├── demo-e2e.sh              # End-to-end local demo (Git Bash friendly)
└── .env.example             # Template for env vars
```

## Prerequisites

* Docker (with Compose)
* Foundry: `forge`, `cast`
* Node.js + npm (`npx`, `npm`)
* `curl` (CLI)
* **Optional:** `jq` (pretty-prints the 8030 status if present)

## Quickstart (Local Graph + Demo)

```bash
# 1) Clone and enter
git clone https://github.com/yourusername/omnichain-lvr-shielded-lp-vault.git
cd omnichain-lvr-shielded-lp-vault

# 2) Create your env
cp .env.example .env
# Fill in RPC_URL, PRIVATE_KEY, HOOK, VAULT, POOL_ID (bytes32), etc.

# 3) Run the demo (starts Graph+IPFS, deploys subgraph, sends 3 txs)
./demo-e2e.sh
```

What you’ll see:

* Docker stack spin-up (IPFS, Postgres, Graph Node)
* Subgraph compile & deploy to the local node
* 3 on-chain demo transactions with receipts
* A wait loop until the subgraph `_meta.block.number` >= **max** demo block
* A GraphQL result set with exactly those 3 events (both `ModeApplied` and `Signal`)

## Environment

Set in `.env` (or export in your shell):

```
# chain + signer
RPC_URL=...
PRIVATE_KEY=0x...

# deployed contracts (Unichain Sepolia)
VAULT=0x84a4871295867f587B15EAFF82e80eA2EbA79a6C
HOOK=0x20c519Cca0360468C0eCd7A74bEc12b9895C44c0
POOL_ID=0x000000000000000000000000000000000000000000000000000000000000457f

# local graph
GRAPH_HTTP_URL=http://127.0.0.1:8000
GRAPH_NODE_URL=http://127.0.0.1:8020
IPFS_URL=http://127.0.0.1:5001
SUBGRAPH_NAME=lvr-shield
VERSION_LABEL=v0.0.1
```

> The subgraph manifest (`subgraph/subgraph.yaml`) pins `startBlock` around the first deploy (e.g., `28554700`) and the contract addresses above so indexing starts at the right height.

## Local Subgraph Stack

`subgraph/docker-compose.yml` exposes:

* **8000** – GraphQL query endpoint
* **8020** – Graph Node admin (JSON-RPC)
* **8030** – Indexing status GraphQL (enabled via `- "8030:8030"`)
* **5001** – IPFS API

Endpoints (local):

* Query: `http://127.0.0.1:8000/subgraphs/name/lvr-shield`
* GraphiQL: `http://127.0.0.1:8000/subgraphs/name/lvr-shield/graphql`
* Indexing status: `http://127.0.0.1:8030/graphql`

## Demo Script: What It Does

`./demo-e2e.sh` (Windows Git Bash friendly):

1. **Start** the Graph/IPFS docker stack and wait for admin JSON-RPC (8020).
2. **Build & deploy** the subgraph (`npx graph deploy …`).
3. **Send three demo txs** calling:

   ```
   adminApplyModeForDemo(
     poolId, mode, epoch,
     reason, centerTick, halfWidthTicks
   )
   ```

   The script chooses epochs based on the current time, sets reasons (`risk-off-demo`, `widen-demo`, `normal-demo`), and emits:

   * `Signal` from the **Hook** (address = `HOOK`)
   * `ModeApplied` from the **Vault** (address = `VAULT`)
4. **Verify on-chain** logs (last \~450–500 blocks).
5. **Wait for indexing**: polls `_meta.block.number` until it reaches the highest demo block.
6. **Print exact GraphQL** that selects the 3 demo transactions (by `transactionHash_in`) and a compact “last 3” query.

If `jq` is installed, the script will also pretty-print `indexingStatuses` from `:8030`.

## GraphQL Queries

### Last 3 mode changes + signals (by block desc)

```graphql
{
  modeApplieds(
    where:{poolId:"0x…457f"},
    first:3, orderBy:blockNumber, orderDirection:desc
  ) {
    id mode epoch centerTick halfWidthTicks blockNumber transactionHash
  }
  signals(
    where:{poolId:"0x…457f"},
    first:3, orderBy:blockNumber, orderDirection:desc
  ) {
    id spotTick ewmaTick sigmaTicks blockNumber transactionHash
  }
}
```

### Exact demo transactions (script prints this too)

```graphql
{
  modeApplieds(
    where:{
      poolId:"0x…457f",
      transactionHash_in:["0xTX1","0xTX2","0xTX3"]
    },
    first:3, orderBy:blockNumber, orderDirection:asc
  ) {
    id mode epoch centerTick halfWidthTicks blockNumber transactionHash
  }
  signals(
    where:{
      poolId:"0x…457f",
      transactionHash_in:["0xTX1","0xTX2","0xTX3"]
    },
    first:3, orderBy:blockNumber, orderDirection:asc
  ) {
    id spotTick ewmaTick sigmaTicks blockNumber transactionHash
  }
}
```

## Events & Entity Schema

### Emitted On Each Demo Tx

* **Hook → `Signal`**

  * `spotTick`: current tick snapshot
  * `ewmaTick`: exponentially-weighted moving average tick
  * `sigmaTicks`: volatility proxy (in ticks)
* **Vault → `ModeApplied`**

  * `mode`: `0=NORMAL`, `1=WIDENED`, `2=RISK_OFF`
  * `epoch`, `centerTick`, `halfWidthTicks`
  * `reason` stored in the event data (mapped into the subgraph)

> In the subgraph, both entities carry the same `transactionHash` so you can correlate the pair for a given epoch/tx.

### Example Entity Fields

* `ModeApplied`: `id`, `poolId`, `mode`, `epoch`, `centerTick`, `halfWidthTicks`, `blockNumber`, `transactionHash`
* `Signal`: `id`, `poolId`, `spotTick`, `ewmaTick`, `sigmaTicks`, `blockNumber`, `transactionHash`

## Signals vs Modes (How They Correlate)

* A **Signal** records telemetry for that epoch (spot/ewma/sigma). Consecutive signals can share identical values (e.g., `{50,50,100}`) if price doesn’t move.
* The **mode** is chosen by rules (thresholds, hysteresis, dwell times, confirmations). That means identical signal tuples can still correspond to *different* modes depending on **state and recent history**.
* In the demo, `adminApplyModeForDemo` explicitly applies a mode per tx so you’ll always get one `Signal` + one `ModeApplied`. Correlate via `transactionHash` rather than assuming one-to-one mapping from `{spot,ewma,sigma}` to a specific mode.

## Contracts & Admin

Some handy calls with `cast`:

```bash
# Read Hook config
cast call $HOOK "cfg()(uint16,uint16,uint16,uint32,uint8,uint32,int24,uint32,uint16,int24,int24)" --rpc-url $RPC_URL

# Demo mode application (used by the script)
cast send $HOOK \
  "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
  $POOL_ID 2 $EPOCH "risk-off-demo" 0 500 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --legacy
```

## Testing & Gas

```bash
forge build
forge test -vvv
forge test --gas-report
```

* Tests cover Hook permissions/config, mode transitions, and Vault integration.

## Troubleshooting

* **“Empty reply from server” while waiting for 8020**
  Normal during Graph Node startup; the script retries until admin JSON-RPC is ready.
* **Graph query returns nothing right after sending tx**
  The script **waits** until `_meta.block.number` ≥ your highest demo block. If you run custom txs, make sure your `startBlock` and addresses in `subgraph.yaml` align with where your contracts live.
* **Indexing status empty**
  Ensure docker maps `- "8030:8030"` and you’re querying `http://127.0.0.1:8030/graphql`.
* **Different counts in results**
  If one of the three demo txs fails on-chain, the script will print successful vs failed txs and the query will naturally include only the successes.

## Roadmap

* Cross-chain broadcasting (LayerZero v2)
* Dynamic fee params by mode
* Multi-oracle aggregation
* Keeper automation (Chainlink/Gelato)
* UI dashboard (positions + telemetry)

## License

MIT

---
