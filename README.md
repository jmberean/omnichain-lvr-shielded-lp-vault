here’s the **super-short TL;DR** that matches your current working setup on Windows (Git Bash). copy/paste straight through.

---

## TL;DR — local e2e run, test, verify

### 0) prereqs

* Docker Desktop (running)
* Foundry (`anvil`, `forge`, `cast`) — `foundryup`
* Node 18+ (npm works)

---

### 1) start chain

```bash
anvil
```

Keep this terminal open.

---

### 2) deploy contracts (new terminal)

```bash
cd omnichain-lvr-shielded-lp-vault
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key "$PK" -vvvv
```

Copy the **Vault** and **Hook** addresses printed in the logs.

---

### 3) set envs (paste your actual addresses)

```bash
export VAULT=0x...   # from deploy logs
export HOOK=0x...    # from deploy logs
export FROM=$(cast wallet address --private-key "$PK")
```

---

### 4) boot the graph stack

```bash
docker compose -f subgraph/docker-compose.yml up -d
docker logs -f subgraph-graph-node-1   # Ctrl+C when “Setup finished…”
```

> docker compose expects `ethereum: "localhost:http://host.docker.internal:8545"` in `graph-node` env (your file already has this).

---

### 5) point manifest at your addresses (lowercase)

```bash
export VAULT_LC=$(echo "$VAULT" | tr '[:upper:]' '[:lower:]')
export HOOK_LC=$(echo "$HOOK"  | tr '[:upper:]' '[:lower:]')

echo $VAULT_LC
echo $HOOK_LC
```
Open the manifest (subgraph/subgraph.yaml) in your editor of choice.

Find the two address: fields under your Vault and LVRShieldHook data sources.

Replace their values with your lowercase addresses:

source:
  abi: Vault
  address: '0x851356ae760d987e095750cceb3bc6014560891c'
...
source:
  abi: LVRShieldHook
  address: '0x95401dc811bb5740090279ba06cfa8fcf6113778'

---

### 6) codegen, build, deploy subgraph

```bash
npm run graph:codegen
npm run graph:build
npx graph create --node http://127.0.0.1:8020 lvr/local || true
npx graph deploy \
  --node http://127.0.0.1:8020 --ipfs http://127.0.0.1:5001 \
  --version-label v0.0.1 \
  lvr/local subgraph/subgraph.yaml
```

You should see:

```
Deployed to http://127.0.0.1:8000/subgraphs/name/lvr/local/graphql
```

---

### 7) emit events (⚠️ note the `--` before negative int)

```bash
# set keeper
cast send --rpc-url http://127.0.0.1:8545 --private-key "$PK" \
  "$VAULT" "setKeeper(address)" "$FROM"

# LiquidityAction (negative param needs `--`)
cast send --rpc-url http://127.0.0.1:8545 --private-key "$PK" \
  "$VAULT" "keeperRebalance(int256,int256,string)" \
  1000000000000000000 -- -3000000000000000000 "demo"

# Signal
cast send --rpc-url http://127.0.0.1:8545 --private-key "$PK" \
  "$HOOK" "poke()"
```

---

### 8) verify data

GraphiQL: open
`http://127.0.0.1:8000/subgraphs/name/lvr/local/graphql`

CLI:

```bash
# Signals
curl -s -X POST http://127.0.0.1:8000/subgraphs/name/lvr/local \
  -H 'content-type: application/json' \
  --data '{"query":"{ signals(first:3, orderBy:blockNumber, orderDirection:desc){ id txHash blockNumber } }"}'

# LiquidityActions
curl -s -X POST http://127.0.0.1:8000/subgraphs/name/lvr/local \
  -H 'content-type: application/json' \
  --data "{\"query\":\"{ liquidityActions(first:3, orderBy:blockNumber, orderDirection:desc){ id reason txHash blockNumber } }\"}"
```

---

### quick fixes

* **restarted anvil → “provider went backwards”**

  ```bash
  docker compose -f subgraph/docker-compose.yml down -v
  docker compose -f subgraph/docker-compose.yml up -d
  # then redo step 6 (deploy subgraph) after redeploying contracts
  ```
* **wallet error on `cast send`**: ensure all `--rpc-url` & `--private-key` flags are **before** function args; keep `--` only to prefix the negative value.
* **redeployed contracts**: repeat **steps 3, 5, 6** (addresses change).
