Here's a drop-in `README.md` that recaps the project, shows what we achieved vs. the original goal, and gives clear setup/test/deploy steps (local + Unichain Sepolia), plus a short troubleshooting section.

---

# Omnichain LVR-Shielded LP Vault (Uniswap v4 on Unichain) — Hackathon Build

**Roles & framing**
You (reader) are acting as **Lead DeFi Engineer & Delivery PM** for a weekend hackathon. The brief: research fast using official docs, plan precisely, ship production-grade code/tests/scripts in small increments, and hand judges a repo that reproduces the demo on the first try.

---

## 0) What we set out to build (original brief)

**Mission**

Build an **Omnichain LVR-Shielded LP Vault** for **Uniswap v4** on **Unichain (primary)** with:

* **v4 Hook** that evaluates price deviation & **eligibility gates** (freshness, hysteresis, dwell, confirmations, `minFlipInterval`) and flips modes: `NORMAL / WIDENED / RISK_OFF`.
* **Vault** with an `onlyHook` “mode apply” entrypoint, optional placement hints (`centerTick/halfWidth`), telemetry events, and a keeper “rebalance record” entrypoint.
* **Subgraph** indexing: `Signal`, `ModeChange/ModeApplied`, `HomeRecorded`, `ReentryDecision`, `Recentered`, `LiquidityAction`.
* Tiny **Scoreboard UI** (optional; can skip but ensure local Graph + clear queries).
* (Optional) **LayerZero v2 OApp** broadcasting `ModeChange A→B` (single message path with LayerZero Scan link).
* (Optional) **Zircuit Garfield** deployment + explorer verification.

**Hard constraints**

* ETHGlobal NYC 2025 deadline **Sun Aug 17, 09:00 EDT** (2–4 min demo video, reproducible repo, clean history).
* Uniswap prize: focus on **Hooks on Unichain**. UI not required; code + README + demo steps + short video are required.
* LayerZero prize (opt): show one on-chain message and include **LayerZero Scan tx hash**.
* Zircuit prize (opt): deploy & **verify** on Zircuit testnet or mainnet; README with test steps.

**Research scope (pre-coding)**

* Uniswap v4 Hooks: address-encoded permission flags, required callbacks, **HookMiner** pattern.
* Unichain testnet/mainnet: PoolManager addresses, fee tiers, tickSpacing behavior, day-of updates.
* Reference price & staleness: acceptable testnet sources (pool spot, mock, Chainlink/Pyth test feeds), how to gate on freshness.
* LayerZero v2 basics: OApp `setPeer`, EIDs, show 1 message with Scan link.
* Zircuit deploy/verify flow.
* The Graph local stack: schema, mappings, codegen/build/deploy via dockerized graph-node + IPFS.

**Architecture requirements**

* **Hook (BaseHook)**

  * Mine a CREATE2 salt so the deployed hook **address encodes permission bits**.
  * `Hooks.validateHookPermissions()` assertions in constructor tests; unit tests for address bits.
  * Maintain: last price/ref, EWMA spot tick, sigma ticks; params: `widenBps, riskOffBps, exitThresholdBps, dwellSec, confirmations, minFlipInterval, homeToleranceTicks, homeTtlSec, kTimes10, minTicks, maxTicks`.
  * Eligibility gates: stale guard, hysteresis (exit < entry), dwell + confirmations, `minFlipInterval`.
  * Placement on entry to NORMAL: decide **HOME vs RECENTER**; compute `center & halfWidth` from sigma; **snap to tickSpacing**.
  * Emit: `Signal`, `ModeChanged`, `HomeRecorded`, `ReentryDecision`, `Recentered`.

* **Vault**

  * `applyMode(poolId, mode, epoch, reason, optCenterTick, optHalfWidthTicks)` with **onlyHook**.
  * Track/expose `getHome(poolId)`; store `lastCenterTick, lastWidthTicks`.
  * `keeperRebalance(...)` event includes current mode & placement ticks.

* **Subgraph**

  * GraphQL schema for the entities above; handlers for Hook/Vault logs; deterministic IDs `(txHash-logIndex)`; include block/timestamp/tx.

* **LayerZero (optional)**

  * Minimal OApp: `broadcastMode(poolId, mode, epoch)`; set EIDs; `setPeer` both chains; show one A→B message with Scan link.

* **Zircuit (optional)**

  * Network config; deploy/verify; README “how to test”.

**Deliverables & layout**

```
/contracts: Hook (v4), Vault, interfaces, libs
/script: Foundry scripts (DeployUnichain.s.sol, DemoFlip.s.sol, EmitTelemetry.s.sol, optional LZSetup)
/subgraph: schema.graphql, subgraph.yaml, mappings/*.ts, docker-compose.yml
/ui (optional): tiny KPI page hitting GraphQL
/README.md: quickstart + judge script + prize sections; addresses; commands; video link
CI: Foundry + graph codegen/build
```

**Process requirements**

* Tests: Hook flags & transitions; staleness/dwell/minFlipInterval/hysteresis; Vault gating; placements; (if time) fuzz.
* Small, gas-sane commits; clear event reasons; minimal storage writes.
* Exact commands & sanity checks for first-run success.

---

## 1) What we actually accomplished

✅ **Contracts (MVP)**

* `Vault.sol` with **onlyHook** gated `applyMode(...)`, telemetry, and keeper pathway.
* `LVRShieldHook.sol` that owns a reference to the `Vault`, exposes `adminApplyModeForDemo(...)` to drive E2E demo (bypasses v4 callbacks), emits demo telemetry, and will be the shell for full BaseHook callbacks.
* `HookCreate2Factory.sol` to deterministically deploy the Hook with **CREATE2** (salted) so address-bits are stable and easy to reason about.

✅ **Unit tests (Foundry)**

* `VaultKeeper.t.sol`: keeper events, only-keeper, placement tracking, `onlyHook` access.
* `LVRShieldHook.t.sol`: permissions surface, config set/get, and a demo path for admin apply.

✅ **Scripts (Foundry)**

* `DeployLocal.s.sol`: local deploy to Anvil, **wires Vault → Hook**, prints addresses & mined **salt**.
* `EmitDemo.s.sol`: sends a demo mode-apply to emit events on both Vault & Hook.

✅ **Local E2E**

* Start Anvil, deploy Vault + Hook, verify mutual wiring via `cast call`, run demo, inspect logs.

✅ **Unichain Sepolia E2E**

* Using **official Unichain Sepolia RPC**, funded test key, deployed Vault + Hook, ran demo (`EmitDemo.s.sol`), and verified two logs (Vault + Hook) via `cast receipt` and `cast tx`.
* Observed & resolved common pitfalls: env var quoting, stale addresses, **nonce too low**, **onlyAdmin** reverts, and Windows CRLF warnings.

❗️**Not yet implemented (TODO to hit full brief)**

* Full **Uniswap v4 BaseHook** callbacks (`afterInitialize`, `beforeSwap/afterSwap`) & true permission-bits validation.
* **Oracle & gating** (freshness, dwell, confirmations, hysteresis, minFlipInterval) driving automatic flips.
* **Placement engine** that snaps to real tickSpacing.
* **Subgraph** + **UI**.
* **LayerZero v2** OApp demo.
* **Zircuit** deploy/verify.

---

## 2) Repo layout (current)

```
contracts/
  hooks/v4/LVRShieldHook.sol
  utils/HookCreate2Factory.sol
  vault/IVault.sol
  vault/Vault.sol

script/
  DeployLocal.s.sol
  EmitDemo.s.sol
  unichain/01_MineAndDeployHook.s.sol   (legacy helper)

test/
  LVRShieldHook.t.sol
  VaultKeeper.t.sol
```

---

## 3) Quickstart — Local (Anvil)

**Prereqs**

* Foundry (`forge`, `cast`, `anvil`) installed.

**Run**

Terminal A (Anvil):

```bash
anvil -b 2
```

Terminal B (project root):

```bash
# Clean & run tests
forge clean && forge test -vvv

# Local deploy (wires Vault -> Hook; prints both addresses + salt)
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # anvil default key 0

forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" --broadcast -vv
```

**Sanity checks**

```bash
export VAULT=<Vault from logs>
export HOOK=<Hook from logs>

cast call "$VAULT" 'hook()(address)'       --rpc-url "$RPC_URL"
cast call "$HOOK"  'VAULT()(address)'      --rpc-url "$RPC_URL"
cast code "$HOOK"  --rpc-url "$RPC_URL" | wc -c   # > 0
```

**Drive the demo**

```bash
export DEMO_HOOK="$HOOK"
export DEMO_POOL_ID=<32-byte poolId from deploy logs, e.g. 0x...>

forge script script/EmitDemo.s.sol:EmitDemo \
  --rpc-url "$RPC_URL" --broadcast -vv

# Inspect the tx (grab hash from script output if needed)
export TX=<tx hash>
cast receipt "$TX" --rpc-url "$RPC_URL"
cast tx      "$TX" --rpc-url "$RPC_URL"
```

You should see **two logs** in the receipt: one from the **Vault** (ModeApplied) and one from the **Hook** (AdminApplyModeForDemo).

---

## 4) Quickstart — Unichain Sepolia (public testnet)

**Prereqs**

* Have **Unichain Sepolia** test ETH on your deployer key (bridge from Ethereum Sepolia → Unichain Sepolia using your preferred Uniswap/official bridge UI).
* Public RPC: `https://sepolia.unichain.org`

**Env & sanity**

```bash
export RPC_URL="https://sepolia.unichain.org"
export ETH_RPC_URL="$RPC_URL"     # optional convenience
export PRIVATE_KEY=<your funded 0x... hex key>

ADDR=$(cast wallet address --private-key "$PRIVATE_KEY"); echo "Deployer: $ADDR"
cast chain-id                 # expect: 1301
cast balance "$ADDR" --ether  # should be > 0
```

**Deploy & wire**

```bash
forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" --broadcast -vv

# Copy from logs:
export VAULT=<printed vault>
export HOOK=<printed hook>
```

**Sanity**

```bash
cast call "$VAULT" 'hook()(address)'      --rpc-url "$RPC_URL"
cast call "$HOOK"  'VAULT()(address)'     --rpc-url "$RPC_URL"
cast code "$HOOK"  --rpc-url "$RPC_URL" | wc -c
```

**Drive the demo**

```bash
export DEMO_HOOK="$HOOK"
export DEMO_POOL_ID=<32-byte poolId printed by deploy>

forge script script/EmitDemo.s.sol:EmitDemo \
  --rpc-url "$RPC_URL" --broadcast -vv

# Inspect
TX=<tx hash from script>
cast receipt "$TX" --rpc-url "$RPC_URL"
cast tx      "$TX" --rpc-url "$RPC_URL"
```

**(Optional) Set config (admin-only)**

```bash
# Confirm admin matches your deployer:
cast call "$HOOK" "admin()(address)" --rpc-url "$RPC_URL"
echo "$ADDR"

# Then write config (add a gas limit to avoid underestimation):
cast send "$HOOK" \
  "setLVRConfig(uint16,uint16,uint32)" 100 1000 300 \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" \
  --gas-limit 200000

# Read back
cast call "$HOOK" "cfg()(uint16,uint16,uint32)" --rpc-url "$RPC_URL"
```

---

## 5) Judge demo (copy-paste script)

```bash
# --- ENV ---
export RPC_URL="https://sepolia.unichain.org"
export PRIVATE_KEY=<0x... funded on Unichain Sepolia>
export ETH_RPC_URL="$RPC_URL"

ADDR=$(cast wallet address --private-key "$PRIVATE_KEY"); echo "Deployer: $ADDR"
cast chain-id && cast balance "$ADDR" --ether

# --- DEPLOY ---
forge script script/DeployLocal.s.sol:DeployLocal --rpc-url "$RPC_URL" --broadcast -vv

# Copy from logs:
export VAULT=<vault>
export HOOK=<hook>
export DEMO_POOL_ID=<32-byte poolId from logs>

# --- SANITY ---
cast call "$VAULT" 'hook()(address)'
cast call "$HOOK"  'VAULT()(address)'
cast code "$HOOK" | wc -c

# --- DEMO EVENT ---
export DEMO_HOOK="$HOOK"
forge script script/EmitDemo.s.sol:EmitDemo --rpc-url "$RPC_URL" --broadcast -vv

# Replace with the printed tx hash:
TX=<hash>
cast receipt "$TX" && cast tx "$TX"
```

What judges should see:

* Two addresses (Vault & Hook), correctly wired.
* Demo tx emits two logs (Vault + Hook).
* Bytecode exists on Hook address.

---

## 6) Troubleshooting

* **“nonce too low”**
  Another tx used that nonce. Let `cast` pick the nonce, or pass the current one explicitly:

  ```bash
  cast send <to> <sig> ... --nonce $(cast nonce "$ADDR" --rpc-url "$RPC_URL")
  ```

* **`execution reverted` on `setLVRConfig`**
  Most likely **not admin**. Confirm `cast call "$HOOK" "admin()(address)"` equals `$ADDR`. If not, redeploy and ensure you export the **new** addresses.

* **Mixing old/new addresses**
  Always `export VAULT` and `export HOOK` from the **latest** deploy logs before running commands. If outputs look wrong, you’re probably querying a previous deployment.

* **Windows CRLF warnings**
  Harmless. If scripts fail on Windows shells, prefer Git Bash and mind quoting (no angle brackets).

* **“block is out of range” / “call to non-contract address”**
  Usually stale configuration or RPC pointed at the wrong network. Re-export `RPC_URL`, `VAULT`, `HOOK`, and retry.

---

## 7) Roadmap to full brief (next steps)

* Implement full **BaseHook** callbacks & permission-bit encoding/mining; add `Hooks.validateHookPermissions()` tests.
* Add **oracle + gating** (freshness, dwell, confirmations, hysteresis, `minFlipInterval`), and real placement w/ tickSpacing snap.
* **Subgraph**: schema + handlers for `Signal`, `ModeApplied`, `HomeRecorded`, `ReentryDecision`, `Recentered`, `LiquidityAction`; sample queries.
* (Optional) **LayerZero v2** OApp for cross-chain ModeChange broadcast + Scan link in README.
* (Optional) **Zircuit** deploy & **verify**, with minimal test steps.

---

## 8) Status snapshot (for the submission)

* **Local tests**: ✅ 100% passing (`VaultKeeper.t.sol`, `LVRShieldHook.t.sol`).
* **Local deploy**: ✅ Vault + Hook wired; demo emits expected events.
* **Unichain Sepolia deploy**: ✅ Public RPC; Vault + Hook wired; demo tx confirmed with two logs.
* **Remaining**: full v4 integration, indexing, and optional cross-chain/UI/Zircuit.

---
