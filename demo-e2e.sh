#!/usr/bin/env bash
# LVR Shielded LP Vault – Streamlined E2E Demo
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "❌ ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing '$1'. Install and re-run."; }
info() { echo "→ $*"; }
success() { echo "✓ $*"; }

# --- prerequisites ---
require_cmd docker
require_cmd curl
require_cmd npx
require_cmd npm
require_cmd cast

# --- load env ---
if [ -f "$ROOT_DIR/.env" ]; then
  . "$ROOT_DIR/.env"
else
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

# --- globals ---
declare -g DEMO_MAX_BLOCK=0
declare -a OK_HASHES=()
declare -a FAILED_HASHES=()

# Quiet receipt check - returns block number only
wait_for_receipt() {
  local tx="$1"
  for i in {1..60}; do
    if out="$(cast receipt "$tx" --rpc-url "$RPC_URL" 2>/dev/null)"; then
      local status="$(printf "%s\n" "$out" | awk '/^[[:space:]]*status[[:space:]]/ {print $2; exit}')"
      local bn="$(printf "%s\n" "$out" | awk '/^[[:space:]]*blockNumber[[:space:]]/ {print $2; exit}')"
      if [ "$status" = "1" ]; then
        OK_HASHES+=("$tx")
        echo -n "$bn"
        return 0
      else
        FAILED_HASHES+=("$tx")
        echo -n "FAILED"
        return 1
      fi
    fi
    printf "." >&2
    sleep 1
  done
  echo -n "TIMEOUT"
  return 1
}

start_graph_stack() {
  info "Starting Graph stack..."
  pushd "$ROOT_DIR/subgraph" >/dev/null
    docker compose down -v >/dev/null 2>&1 || true
    docker compose up -d >/dev/null 2>&1
  popd >/dev/null

  printf "  Waiting for Graph Node"
  until curl -fsS -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","id":"1","method":"subgraph_list"}' \
      "$GRAPH_NODE_URL" >/dev/null 2>&1; do
    printf "."
    sleep 2
  done
  echo " ready!"
}

deploy_subgraph() {
  info "Deploying subgraph..."
  pushd "$ROOT_DIR/subgraph" >/dev/null
    npm run build >/dev/null 2>&1
    npx graph create --node "$GRAPH_NODE_URL" "$SUBGRAPH_NAME" >/dev/null 2>&1 || true
    npx graph deploy \
      --node "$GRAPH_NODE_URL" \
      --ipfs "$IPFS_URL" \
      --version-label "$VERSION_LABEL" \
      "$SUBGRAPH_NAME" >/dev/null 2>&1
  popd >/dev/null
  success "Subgraph deployed"
}

send_demo_transactions() {
  info "Sending demo transactions..."
  ME=$(cast wallet address --private-key "$PRIVATE_KEY")
  NONCE=$(cast nonce "$ME" --rpc-url "$RPC_URL" --block pending)
  GAS=$(cast gas-price --rpc-url "$RPC_URL")
  GAS=$(( GAS + GAS/10 ))

  E0=$(( $(date +%s) % 100000 ))
  E1=$(( E0 + 1 ))
  E2=$(( E0 + 2 ))

  echo "  Account: ${ME:0:10}... | Nonce: $NONCE | Epochs: $E0,$E1,$E2"

  # Send all 3 transactions
  printf "  [1/3] RISK_OFF  "
  TX1=$(cast send "$HOOK" \
    "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
    "$POOL_ID" 2 "$E0" "risk-off-demo" 0 500 \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --legacy \
    --nonce "$NONCE" --gas-price "$GAS" --async 2>/dev/null | tail -n1 | tr -d '\r')
  BN1="$(wait_for_receipt "$TX1" || true)"
  echo " → Block: $BN1"

  NONCE=$(( NONCE + 1 ))
  printf "  [2/3] WIDENED   "
  TX2=$(cast send "$HOOK" \
    "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
    "$POOL_ID" 1 "$E1" "widen-demo" 50 100 \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --legacy \
    --nonce "$NONCE" --gas-price "$GAS" --async 2>/dev/null | tail -n1 | tr -d '\r')
  BN2="$(wait_for_receipt "$TX2" || true)"
  echo " → Block: $BN2"

  NONCE=$(( NONCE + 1 ))
  printf "  [3/3] NORMAL    "
  TX3=$(cast send "$HOOK" \
    "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
    "$POOL_ID" 0 "$E2" "normal-demo" 50 100 \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --legacy \
    --nonce "$NONCE" --gas-price "$GAS" --async 2>/dev/null | tail -n1 | tr -d '\r')
  BN3="$(wait_for_receipt "$TX3" || true)"
  echo " → Block: $BN3"

  # Calculate max block
  BN1="${BN1:-0}"; BN2="${BN2:-0}"; BN3="${BN3:-0}"
  DEMO_MAX_BLOCK="$BN1"
  [ "$BN2" -gt "$DEMO_MAX_BLOCK" ] 2>/dev/null && DEMO_MAX_BLOCK="$BN2"
  [ "$BN3" -gt "$DEMO_MAX_BLOCK" ] 2>/dev/null && DEMO_MAX_BLOCK="$BN3"
  if [ "$DEMO_MAX_BLOCK" -eq 0 ] || [[ "$DEMO_MAX_BLOCK" == *"FAILED"* ]] || [[ "$DEMO_MAX_BLOCK" == *"TIMEOUT"* ]]; then
    DEMO_MAX_BLOCK="$(cast block-number --rpc-url "$RPC_URL")"
  fi

  success "${#OK_HASHES[@]} successful, ${#FAILED_HASHES[@]} failed"
}

verify_onchain() {
  info "Verifying on-chain events..."
  LATEST=$(cast block-number --rpc-url "$RPC_URL")
  FROM=$((LATEST-450)); [ $FROM -lt 1 ] && FROM=1
  
  # Count events instead of showing all logs
  VAULT_LOGS=$(cast logs --from-block "$FROM" --to-block latest --address "$VAULT" --rpc-url "$RPC_URL" 2>/dev/null | grep -c "0x" || echo "0")
  HOOK_LOGS=$(cast logs --from-block "$FROM" --to-block latest --address "$HOOK" --rpc-url "$RPC_URL" 2>/dev/null | grep -c "0x" || echo "0")
  
  echo "  Vault events: $VAULT_LOGS | Hook events: $HOOK_LOGS"
}

wait_until_indexed() {
  local target="$1"
  printf "  Waiting for subgraph to reach block $target"
  while :; do
    local meta
    meta=$(curl -s -H "Content-Type: application/json" \
      -d '{"query":"{ _meta { block { number } } }"}' \
      "$GRAPH_HTTP_URL/subgraphs/name/$SUBGRAPH_NAME" 2>/dev/null \
      | sed -n 's/.*"number":\([0-9][0-9]*\).*/\1/p')
    if [ -n "$meta" ] && [ "$meta" -ge "$target" ] 2>/dev/null; then
      echo " → indexed at $meta"
      break
    fi
    printf "."
    sleep 2
  done
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
  info "Querying subgraph..."
  
  # Build the full query
  local QUERY
  QUERY="$(_build_demo_query)"
  
  # Execute compact query for counting
  local query_compact=""
  if [ "${#OK_HASHES[@]}" -gt 0 ]; then
    local txs_json="["
    for h in "${OK_HASHES[@]}"; do txs_json="$txs_json\"$h\","; done
    txs_json="${txs_json%,}]"
    query_compact="{ modeApplieds(where:{poolId:\"$POOL_ID\", transactionHash_in:$txs_json}, first: 3) { mode epoch } signals(where:{poolId:\"$POOL_ID\", transactionHash_in:$txs_json}, first: 3) { spotTick } }"
  else
    query_compact="{ modeApplieds(where:{poolId:\"$POOL_ID\"}, first: 3) { mode epoch } signals(where:{poolId:\"$POOL_ID\"}, first: 3) { spotTick } }"
  fi

  # Query and count results
  local response
  response=$(curl -sS -H "Content-Type: application/json" \
    -d "{\"query\":\"$(echo "$query_compact" | tr '\n' ' ' | sed 's/\"/\\\"/g')\"}" \
    "$GRAPH_HTTP_URL/subgraphs/name/$SUBGRAPH_NAME" 2>/dev/null)
  
  local mode_count=$(echo "$response" | grep -o '"mode"' | wc -l)
  local signal_count=$(echo "$response" | grep -o '"spotTick"' | wc -l)
  
  success "Found $mode_count mode changes, $signal_count signals"
  echo ""
  echo "📊 GraphiQL UI: $GRAPH_HTTP_URL/subgraphs/name/$SUBGRAPH_NAME/graphql"
  echo ""
  echo "📋 Copy this query to GraphiQL:"
  echo "--------------------------------"
  echo "$QUERY"
}

# --- Main execution ---
echo "═══════════════════════════════════════════════════════"
echo " LVR Shield Demo - Starting"
echo "═══════════════════════════════════════════════════════"

start_graph_stack
deploy_subgraph
send_demo_transactions
verify_onchain
info "Syncing subgraph..."
wait_until_indexed "$DEMO_MAX_BLOCK"
verify_subgraph

echo "═══════════════════════════════════════════════════════"
echo " ✅ Demo Complete!"
echo "═══════════════════════════════════════════════════════"