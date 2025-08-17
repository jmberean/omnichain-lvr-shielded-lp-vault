#!/usr/bin/env bash
set -euo pipefail

# ---- config (envs expected) ----
: "${PRIVATE_KEY:?Set PRIVATE_KEY (0x... funded on Unichain Sepolia)}"
if [[ -z "${RPC_URL:-}" ]]; then
  : "${ALCHEMY_KEY:?Set ALCHEMY_KEY or RPC_URL}"
  export RPC_URL="https://unichain-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}"
fi
export ETH_RPC_URL="$RPC_URL"

# ---- sanity ----
echo "RPC    : $RPC_URL"
ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Sender : $ADDR"
echo "Chain  : $(cast chain-id)"
echo "Block  : $(cast block-number)"
echo "Balance: $(cast balance "$ADDR" --ether) ETH"

# ---- deploy (skip sim to avoid 'block out of range') ----
LOGDEP="$(mktemp -t deploy_XXXX.txt)"
forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" --broadcast --skip-simulation --sender "$ADDR" -vv \
  | tee "$LOGDEP"

# Strip ANSI once for stable parsing
CLEAN_LOG="$(mktemp -t deploy_clean_XXXX.txt)"
sed -r 's/\x1B\[[0-9;]*[mK]//g' "$LOGDEP" > "$CLEAN_LOG"

# Parse addresses + salt from the clean log
VAULT="$(grep -Eo 'Vault[[:space:]]*:[[:space:]]*0x[0-9a-fA-F]{40}' "$CLEAN_LOG" | tail -n1 | sed -E 's/.*:\s*(0x[0-9a-fA-F]{40}).*/\1/')"
HOOK="$(grep -Eo 'Hook[[:space:]]*:[[:space:]]*0x[0-9a-fA-F]{40}' "$CLEAN_LOG"  | tail -n1 | sed -E 's/.*:\s*(0x[0-9a-fA-F]{40}).*/\1/')"
SALT="$(grep -Eo '0x[0-9a-fA-F]{64}' "$CLEAN_LOG" | tail -n1)"

if [[ -z "$VAULT" || -z "$HOOK" ]]; then
  echo "!! Could not parse Vault/Hook from deploy output. See $LOGDEP" >&2
  exit 1
fi

echo "Vault  : $VAULT"
echo "Hook   : $HOOK"
[[ -n "$SALT" ]] && echo "Salt   : $SALT"

# ---- sanity: wire check ----
echo "Vault.hook() => $(cast call "$VAULT" 'hook()(address)')"
echo "Hook.VAULT() => $(cast call "$HOOK"  'VAULT()(address)')"
echo "Hook code    => $(cast code "$HOOK" | wc -c | tr -d '[:space:]') bytes"

# ---- demo tx: emit a ModeApplied on Vault via Hook admin demo ----
export DEMO_HOOK="$HOOK"
# Prefer the mined salt as poolId; else a fixed demo id
POOL_ID="${POOL_ID:-${SALT:-0x0000000000000000000000000000000000000000000000000000000000001b8e}}"
export DEMO_POOL_ID="$POOL_ID"
echo "POOL_ID: $POOL_ID"

forge script script/EmitDemo.s.sol:EmitDemo \
  --rpc-url "$RPC_URL" --broadcast --skip-simulation -vv

# ---- quick telemetry: pull events from chain (last 1000 blocks) ----
echo
echo "== Telemetry (chunked fetch to satisfy 500-block RPC limit) =="
CUR=$(cast block-number --rpc-url "$RPC_URL")
WINDOW=${WINDOW:-1000}
CHUNK=450
FROM=$(( CUR > WINDOW ? CUR - WINDOW : 0 ))
echo "Scanning blocks: $FROM → $CUR in chunks of $CHUNK"

scan_range() {
  local ADDR="$1"
  local TOPIC0="$2"
  local start="$FROM"
  while [ "$start" -le "$CUR" ]; do
    local end=$(( start + CHUNK ))
    [ "$end" -gt "$CUR" ] && end="$CUR"
    cast logs --address "$ADDR" "$TOPIC0" \
      --from-block "$start" --to-block "$end" \
      --rpc-url "$RPC_URL" || true
    start=$(( end + 1 ))
  done
}

MODE_APPLIED_TOPIC=0x0c69646e72ea74be13ab35ced3070c7c4098fbd2ea88ba07f4b90db9acd04927
ADMIN_ACTION_TOPIC=0xe9f28e6441424e1e39e8a85cf128b7e196f206194acba77a5bd63607734e4e67

echo
echo "== ModeApplied (Vault) =="
scan_range "$VAULT" "$MODE_APPLIED_TOPIC"

echo
echo "== Admin demo (Hook) =="
scan_range "$HOOK"  "$ADMIN_ACTION_TOPIC"



echo
echo "Summary:"
echo "  VAULT = $VAULT"
echo "  HOOK  = $HOOK"
echo "  POOL  = $POOL_ID"

# Save addresses to a file for later scripts
{
  echo "UNICHAIN_SEPOLIA_VAULT=$VAULT"
  echo "UNICHAIN_SEPOLIA_HOOK=$HOOK"
  echo "UNICHAIN_SEPOLIA_POOLID=$POOL_ID"
} > .env.unichain
echo "Wrote .env.unichain"
