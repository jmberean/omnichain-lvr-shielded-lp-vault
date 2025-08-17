#!/usr/bin/env bash
# LVR Shielded LP Vault — End-to-End Demo (Windows Git Bash friendly)
# - Starts local Graph Node + IPFS (Docker)
# - Deploys the subgraph "lvr-shield"
# - Sends 3 on-chain demo signals (RISK_OFF → WIDENED → NORMAL)
# - Waits for subgraph indexing to include those blocks
# - Verifies on-chain events and subgraph queries
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing '$1'. Install and re-run."; }

# --- prerequisites (jq is optional; used only if present) ---
require_cmd docker
require_cmd curl
require_cmd npx
require_cmd npm
require_cmd cast

# --- load env ---
if [ -f "$ROOT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env"
else
  echo "No .env found at repo root; falling back to defaults from .env.example"
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env.example"
fi

: "${GRAPH_NODE_URL:=http://127.0.0.1:8020}"
: "${GRAPH_HTTP_URL:=http://127.0.0.1:8000}"
: "${IPFS_URL:=http://127.0.0.1:5001}"
: "${VERSION_LABEL:=v0.0.1}"
: "${SUBGRAPH_NAME:=lvr-shield}"

: "${RPC_URL:?RPC_URL not set}"
: "${PRIVATE_KEY:?PRIVATE_KEY not set}"
: "${VAULT:?VAULT not set}"
: "${HOOK:?HOOK not set}"
: "${POOL_ID:?POOL_ID not set}"

# --- globals for demo receipts & dynamic GraphQL ---
declare -g DEMO_MAX_BLOCK=0
declare -a OK_HASHES=()
declare -a FAILED_HASHES=()
declare -g LAST_STATUS=""

# Print receipt (stderr), echo block number (stdout), and set LAST_STATUS
wait_for_receipt() {
  local tx="$1"
  LAST_STATUS=""
  for i in {1..60}; do
    if out="$(cast receipt "$tx" --rpc-url "$RPC_URL" 2>/dev/null)"; then
      # Show human-readable receipt in console
      echo "$out" >&2
      # Parse status (0/1) and decimal block number
      LAST_STATUS="$(printf "%s\n" "$out" | awk '/^[[:space:]]*status[[:space:]]/ {print $2; exit}')"
      local bn
      bn="$(printf "%s\n" "$out" | awk '/^[[:space:]]*blockNumber[[:space:]]/ {print $2; exit}')"
      [ -n "$bn" ] && echo "$bn"
      return 0
    fi
    sleep 1
  done
  echo "WARN: receipt $tx not found within 60s" >&2
  return 1
}

start_graph_stack() {
  echo "==> Starting Graph stack (docker compose) ..."
  pushd "$ROOT_DIR/subgraph" >/dev/null
    docker compose down -v >/dev/null 2>&1 || true
    docker compose up -d
  popd >/dev/null

  echo "==> Waiting for Graph Node admin JSON-RPC ($GRAPH_NODE_URL)"
  # Admin JSON-RPC needs POST; GET will return empty reply (expected)
  until curl -fsS -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","id":"1","method":"subgraph_list"}' \
      "$GRAPH_NODE_URL" >/dev/null; do
    echo "waiting for graph-node…"; sleep 2
  done
}

deploy_subgraph() {
  echo "==> Building & deploying subgraph to local node ..."
  pushd "$ROOT_DIR/subgraph" >/dev/null
    npm run build
    npx graph create --node "$GRAPH_NODE_URL" "$SUBGRAPH_NAME" || true
    npx graph deploy \
      --node "$GRAPH_NODE_URL" \
      --ipfs "$IPFS_URL" \
      --version-label "$VERSION_LABEL" \
      "$SUBGRAPH_NAME"
  popd >/dev/null
}

send_demo_transactions() {
  echo "==> Preparing on-chain demo transactions ..."
  ME=$(cast wallet address --private-key "$PRIVATE_KEY")
  NONCE=$(cast nonce "$ME" --rpc-url "$RPC_URL" --block pending)

  GAS=$(cast gas-price --rpc-url "$RPC_URL")
  GAS=$(( GAS + GAS/10 )) # +10% to avoid "already known"

  E0=$(( $(date +%s) % 100000 ))
  E1=$(( E0 + 1 ))
  E2=$(( E0 + 2 ))

  echo "Account:        $ME"
  echo "Start nonce:    $NONCE"
  echo "Gas (wei):      $GAS"
  echo "Epochs:         $E0, $E1, $E2"

  echo "==> 1) RISK_OFF (2)"
  TX1=$(
    cast send "$HOOK" \
      "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
      "$POOL_ID" 2 "$E0" "risk-off-demo" 0 500 \
      --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --legacy \
      --nonce "$NONCE" --gas-price "$GAS" --async \
    | tail -n1 | tr -d '\r'
  )
  NONCE=$(( NONCE + 1 ))
  BN1="$(wait_for_receipt "$TX1" || true)"
  if [ "${LAST_STATUS:-0}" = "1" ]; then OK_HASHES+=("$TX1"); else FAILED_HASHES+=("$TX1"); fi

  echo "==> 2) WIDENED (1)"
  TX2=$(
    cast send "$HOOK" \
      "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
      "$POOL_ID" 1 "$E1" "widen-demo" 50 100 \
      --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --legacy \
      --nonce "$NONCE" --gas-price "$GAS" --async \
    | tail -n1 | tr -d '\r'
  )
  NONCE=$(( NONCE + 1 ))
  BN2="$(wait_for_receipt "$TX2" || true)"
  if [ "${LAST_STATUS:-0}" = "1" ]; then OK_HASHES+=("$TX2"); else FAILED_HASHES+=("$TX2"); fi

  echo "==> 3) NORMAL (0)"
  TX3=$(
    cast send "$HOOK" \
      "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
      "$POOL_ID" 0 "$E2" "normal-demo" 50 100 \
      --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --legacy \
      --nonce "$NONCE" --gas-price "$GAS" --async \
    | tail -n1 | tr -d '\r'
  )
  BN3="$(wait_for_receipt "$TX3" || true)"
  if [ "${LAST_STATUS:-0}" = "1" ]; then OK_HASHES+=("$TX3"); else FAILED_HASHES+=("$TX3"); fi

  # Compute max block among receipts (fallback to chain head if missing)
  local head
  head="$(cast block-number --rpc-url "$RPC_URL")"
  BN1="${BN1:-0}"; BN2="${BN2:-0}"; BN3="${BN3:-0}"
  DEMO_MAX_BLOCK="$BN1"
  [ "$BN2" -gt "$DEMO_MAX_BLOCK" ] && DEMO_MAX_BLOCK="$BN2"
  [ "$BN3" -gt "$DEMO_MAX_BLOCK" ] && DEMO_MAX_BLOCK="$BN3"
  [ "$DEMO_MAX_BLOCK" -eq 0 ] && DEMO_MAX_BLOCK="$head"
  echo "Demo tx blocks: BN1=$BN1 BN2=$BN2 BN3=$BN3 → waiting for ≥ $DEMO_MAX_BLOCK"

  echo "Successful demo txs (${#OK_HASHES[@]}): ${OK_HASHES[*]:-none}"
  if [ "${#FAILED_HASHES[@]}" -gt 0 ]; then
    echo "Failed demo txs (${#FAILED_HASHES[@]}): ${FAILED_HASHES[*]}"
  fi
}

verify_onchain() {
  echo "==> Verifying on-chain events (≤500 blocks window) ..."
  LATEST=$(cast block-number --rpc-url "$RPC_URL")
  FROM=$((LATEST-450)); [ $FROM -lt 1 ] && FROM=1

  echo "---- VAULT logs (ModeApplied expected) ----"
  cast logs --from-block "$FROM" --to-block latest --address "$VAULT" --rpc-url "$RPC_URL" || true

  echo "---- HOOK logs (Signal expected) ----"
  cast logs --from-block "$FROM" --to-block latest --address "$HOOK" --rpc-url "$RPC_URL" || true
}

# Poll _meta.block.number until it reaches target
wait_until_indexed() {
  local target="$1"
  echo "Waiting for subgraph to reach block >= $target ..."
  while :; do
    local meta
    meta=$(curl -s -H "Content-Type: application/json" \
      -d '{"query":"{ _meta { block { number } } }"}' \
      "$GRAPH_HTTP_URL/subgraphs/name/$SUBGRAPH_NAME" \
      | sed -n 's/.*"number":\([0-9][0-9]*\).*/\1/p')
    [ -n "$meta" ] && echo "  _meta.block.number = $meta"
    if [ -n "$meta" ] && [ "$meta" -ge "$target" ]; then
      echo "Subgraph caught up."
      break
    fi
    sleep 2
  done
}

# Optional: pretty status if 8030 is exposed; harmless if jq missing
print_indexing_status() {
  echo "==> Indexing status (8030)"
  local url="http://127.0.0.1:8030/graphql"
  local payload='{"query":"{ indexingStatuses(subgraphs:[\"'"$SUBGRAPH_NAME"'\"]) { subgraph health synced chains { chainHeadBlock{number} latestBlock{number} } } }"}'
  local res
  res="$(curl -s -H "Content-Type: application/json" -d "$payload" "$url" || true)"
  if command -v jq >/dev/null 2>&1; then
    echo "$res" | jq .
  else
    echo "$res"
  fi
}

_build_demo_query() {
  local arr=()
  for h in "${OK_HASHES[@]}"; do arr+=("\"$h\""); done
  local n=${#arr[@]}
  if [ "$n" -gt 0 ]; then
    local txs_json="[$(IFS=,; echo "${arr[*]}")]"
    cat <<EOF
{
  modeApplieds(
    where:{poolId:"$POOL_ID", transactionHash_in:$txs_json},
    first: $n, orderBy: blockNumber, orderDirection: asc
  ) {
    id mode epoch centerTick halfWidthTicks blockNumber transactionHash
  }
  signals(
    where:{poolId:"$POOL_ID", transactionHash_in:$txs_json},
    first: $n, orderBy: blockNumber, orderDirection: asc
  ) {
    id spotTick ewmaTick sigmaTicks blockNumber transactionHash
  }
}
EOF
  else
    # Fallback if all failed (show latest 3 for the pool)
    cat <<EOF
{
  modeApplieds(where:{poolId:"$POOL_ID"}, first: 3, orderBy: blockNumber, orderDirection: desc) {
    id mode epoch centerTick halfWidthTicks blockNumber transactionHash
  }
  signals(where:{poolId:"$POOL_ID"}, first: 3, orderBy: blockNumber, orderDirection: desc) {
    id spotTick ewmaTick sigmaTicks blockNumber transactionHash
  }
}
EOF
  fi
}

verify_subgraph() {
  echo "==> Verifying in subgraph (GraphQL over HTTP) ..."
  local QUERY
  QUERY="$(_build_demo_query)"

  # POST to Graph Node
  curl -sS -H "Content-Type: application/json" \
    -d "{\"query\":\"$(echo "$QUERY" | tr '\n' ' ' | sed 's/\"/\\\"/g')\"}" \
    "$GRAPH_HTTP_URL/subgraphs/name/$SUBGRAPH_NAME" \
    | sed 's/\\\\n/\n/g' || true

  echo
  echo "Open GraphiQL UI in browser for pretty view:"
  echo "  $GRAPH_HTTP_URL/subgraphs/name/$SUBGRAPH_NAME/graphql"
  echo
  echo "Demo-specific query (exact successful txs) — copy/paste into GraphiQL:"
  echo "$QUERY"
}

main() {
  start_graph_stack
  deploy_subgraph
  send_demo_transactions
  verify_onchain
  wait_until_indexed "$DEMO_MAX_BLOCK"
  print_indexing_status || true
  verify_subgraph
  echo "==> Demo complete."
}

main "$@"
