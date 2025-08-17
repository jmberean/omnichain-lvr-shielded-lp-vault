#!/usr/bin/env bash
# e2e-unichain.sh
# End-to-end deploy + demo + subgraph bootstrap for Unichain Sepolia.
# Works in bash / Git Bash. Assumes repo layout from our project.

set -euo pipefail

### -------- helpers --------
need() { command -v "$1" >/dev/null 2>&1 || { echo "✗ Missing dependency: $1" >&2; exit 1; }; }
banner() { printf "\n\033[1;36m== %s ==\033[0m\n" "$*"; }
info()   { printf "\033[0;33m[info]\033[0m %s\n" "$*"; }
ok()     { printf "\033[0;32m[ok]\033[0m %s\n" "$*"; }
err()    { printf "\033[0;31m[err]\033[0m %s\n" "$*" >&2; }

### -------- deps check --------
banner "Checking tools"
need forge
need cast
need node
need npm
need docker
if ! docker info >/dev/null 2>&1; then
  err "Docker daemon not running. Please start Docker Desktop."
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  info "jq not found — will skip auto-parsing some JSON (optional)."
fi

### -------- env & RPC --------
banner "Checking environment"

RPC_URL="${RPC_URL:-}"
ALCHEMY_KEY="${ALCHEMY_KEY:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"

if [[ -z "$RPC_URL" ]]; then
  if [[ -n "$ALCHEMY_KEY" ]]; then
    RPC_URL="https://unichain-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}"
    export RPC_URL
  else
    err "Set RPC_URL or ALCHEMY_KEY. Example: export ALCHEMY_KEY=... (will derive RPC_URL)."
    exit 1
  fi
fi

if [[ -z "$PRIVATE_KEY" ]]; then
  err "Set PRIVATE_KEY (funded Unichain Sepolia key, 0x...)."
  exit 1
fi

export ETH_RPC_URL="$RPC_URL" # make cast/forge use it by default

ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
ok "Deployer: $ADDR"

CID="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$CID" != "1301" ]]; then
  err "Wrong chain-id: $CID (expected 1301 for Unichain Sepolia). Check RPC_URL."
  exit 1
fi
ok "Chain-id: $CID"

BAL="$(cast balance "$ADDR" --ether --rpc-url "$RPC_URL")"
ok "Balance: ${BAL} ETH (Unichain Sepolia)"

### -------- deploy (Vault + Hook) --------
banner "Deploying Vault + Hook to Unichain Sepolia (skip simulation)"

LOGFILE="$(mktemp -t deploy_out_XXXX.txt)"
set +e
forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation \
  --sender "$ADDR" \
  -vv | tee "$LOGFILE"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  err "Forge deploy failed. See $LOGFILE"
  exit $rc
fi

# Strip ANSI colors once
CLEAN_LOG="$(mktemp -t deploy_clean_XXXX.txt)"
sed -r 's/\x1B\[[0-9;]*[mK]//g' "$LOGFILE" > "$CLEAN_LOG"

# Grab addresses from clean log
VAULT="$(grep -Eo 'Vault[[:space:]]*:[[:space:]]*0x[0-9a-fA-F]{40}' "$CLEAN_LOG" \
        | tail -n1 | sed -E 's/.*:\s*(0x[0-9a-fA-F]{40}).*/\1/')"
HOOK="$(grep -Eo 'Hook[[:space:]]*:[[:space:]]*0x[0-9a-fA-F]{40}' "$CLEAN_LOG" \
       | tail -n1 | sed -E 's/.*:\s*(0x[0-9a-fA-F]{40}).*/\1/')"
SALT="$(grep -Eo '0x[0-9a-fA-F]{64}' "$CLEAN_LOG" | tail -n1)"

# Fallback if a bare 0x... line was logged for salt
if [[ -z "${SALT:-}" ]]; then
  SALT="$(grep -Eo '^0x[0-9a-fA-F]{64}$' "$LOGFILE" | tail -n1 || true)"
fi

if [[ -z "$VAULT" || -z "$HOOK" ]]; then
  err "Could not parse Vault/Hook from deploy output. Check $LOGFILE"
  exit 1
fi

ok "Vault : $VAULT"
ok "Hook  : $HOOK"
[[ -n "${SALT:-}" ]] && ok "Salt  : $SALT"

### -------- sanity check on-chain --------
banner "Sanity checks (hook pointers)"
VfromV="$(cast call "$VAULT" 'hook()(address)' --rpc-url "$RPC_URL")"
VfromH="$(cast call "$HOOK"  'VAULT()(address)' --rpc-url "$RPC_URL")"
ok "Vault.hook()        => $VfromV"
ok "Hook.VAULT()        => $VfromH"
CODE_SZ="$(cast code "$HOOK" --rpc-url "$RPC_URL" | wc -c | tr -d '[:space:]')"
ok "Hook bytecode bytes => $CODE_SZ"

### -------- demo emit --------
banner "Demo: emit AdminApplyModeForDemo"
# Prefer user-provided POOL_ID; else use Salt from deploy; else a default padded hex.
POOL_ID="${POOL_ID:-${SALT:-$(printf '0x%064x' 0x1b8e)}}"
ok "POOL_ID: $POOL_ID"

export DEMO_HOOK="$HOOK"
export DEMO_POOL_ID="$POOL_ID"

LOGFILE_DEMO="$(mktemp -t demo_out_XXXX.txt)"
set +e
forge script script/EmitDemo.s.sol:EmitDemo \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation \
  -vv | tee "$LOGFILE_DEMO"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  err "Demo script failed. See $LOGFILE_DEMO"
  exit $rc
fi

TX_HASH=""
if command -v jq >/dev/null 2>&1 && [[ -f "broadcast/EmitDemo.s.sol/1301/run-latest.json" ]]; then
  TX_HASH="$(jq -r '.transactions[-1].hash' broadcast/EmitDemo.s.sol/1301/run-latest.json)"
fi
[[ -n "$TX_HASH" ]] && ok "Demo tx: $TX_HASH"

### -------- subgraph wiring --------
banner "Subgraph: patch YAML (address/startBlock) & wire docker RPC"

SUBYAML="subgraph/subgraph.yaml"
SUBDC="subgraph/docker-compose.yml"

if [[ ! -f "$SUBYAML" || ! -f "$SUBDC" ]]; then
  err "subgraph files not found. Expected subgraph/subgraph.yaml and subgraph/docker-compose.yml"
  exit 1
fi

VAULT_LC="$(echo "$VAULT" | tr '[:upper:]' '[:lower:]')"
# pick a safe start block near the demo (current - 1000)
CUR_BLK="$(cast block-number --rpc-url "$RPC_URL")"
START_BLK=$(( CUR_BLK > 1000 ? CUR_BLK - 1000 : 0 ))

# replace address + startBlock
sed -i.bak -E 's/(address:\s*")[^"]+(")/\1'"$VAULT_LC"'\2/' "$SUBYAML"
sed -i.bak -E 's/(startBlock:\s*)[0-9]+/\1'"$START_BLK"'/' "$SUBYAML"

# point graph-node at your actual RPC (label it unichain-sepolia)
# replace the "ethereum:" line entirely
if grep -q 'ethereum:' "$SUBDC"; then
  sed -i.bak -E 's#(ethereum:\s*").*("#\1unichain-sepolia:'"$RPC_URL"'\2#' "$SUBDC" || true
fi

ok "Updated $SUBYAML (address=$VAULT_LC, startBlock=$START_BLK)"
ok "Updated $SUBDC (ethereum → unichain-sepolia:$RPC_URL)"

### -------- boot graph stack --------
banner "Booting local graph-node stack (ipfs/postgres/graph-node)"
pushd subgraph >/dev/null

# choose compose v2 or v1
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
else
  COMPOSE="docker-compose"
fi

$COMPOSE up -d

### -------- build & deploy subgraph --------
banner "Building & deploying subgraph"
npm install
npm run codegen
npm run build

# Optional scripts; if not present, try raw graph-cli
if npm run | grep -q create-local; then
  npm run create-local || true
else
  info "No npm script create-local — skipping (assuming already created)."
fi

if npm run | grep -q deploy-local; then
  npm run deploy-local
else
  info "No npm script deploy-local — if needed, run graph deploy manually."
fi

popd >/dev/null

### -------- summary --------
banner "Summary"
cat <<EOF
Vault      : $VAULT
Hook       : $HOOK
PoolId     : $POOL_ID
RPC URL    : $RPC_URL
Deployer   : $ADDR
GraphQL    : http://localhost:8000/subgraphs/name/lvr-shield

Sample query (paste into the GraphQL playground):

{
  modeApplieds(first: 10, orderBy: blockNumber, orderDirection: desc) {
    id
    poolId
    mode
    epoch
    reason
    centerTick
    halfWidthTicks
    blockNumber
    blockTimestamp
    transactionHash
  }
}

EOF

ok "E2E completed."
