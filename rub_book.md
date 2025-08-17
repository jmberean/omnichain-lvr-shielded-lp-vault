Here’s the **current, working end-to-end run** for our repo on **Unichain Sepolia** (using Alchemy). It’s copy-pasteable in your Git Bash (`MINGW64`) session and matches exactly what you just succeeded with: deploy Vault+Hook, wire them, run the demo script, and verify logs on-chain.

---

# E2E Run (Unichain Sepolia, Alchemy)

## 0) Env (RPC + key)

```bash
# Alchemy Unichain Sepolia RPC (make sure Unichain Sepolia is enabled for your app in the Alchemy dashboard)
export ALCHEMY_KEY=BUHkMjNrRm3P64Z8tNnct
export RPC_URL="https://unichain-sepolia.g.alchemy.com/v2/$ALCHEMY_KEY"

# Make Foundry use this RPC by default
export ETH_RPC_URL="$RPC_URL"

# Funded Unichain Sepolia private key (the one you’ve been using)
export PRIVATE_KEY=0x9a12079cebb28de053f07d1e38687c278af265c4ab378de24cd2ef4119c69c51

# Derive address + quick checks
ADDR=$(cast wallet address --private-key "$PRIVATE_KEY"); echo "Deployer: $ADDR"
cast chain-id            # expect: 1301
cast block-number
cast nonce "$ADDR"
cast balance "$ADDR" --ether
```

## 1) Deploy (prints Vault / Hook / Salt)

> We skip simulation because public RPCs often can’t fork for Foundry simulations.

```bash
forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation \
  --sender "$ADDR" \
  -vv
```

You’ll see three lines near the top of the logs like:

```
Vault  : 0x...
Hook   : 0x...
0x...  (the mined salt we also reuse as a demo poolId)
```

Set them:

```bash
# paste the two values printed by the deploy
export VAULT=0x9D1993Dc39603bd88631637520c61fD571997cA0
export HOOK=0xD656892746b6ea05Ce19Ec7d18093B7eE9AD00C0
```

## 2) Sanity: wiring + code present

```bash
# Vault knows Hook?
cast call "$VAULT" "hook()(address)"  --rpc-url "$RPC_URL"

# Hook points back to Vault?
cast call "$HOOK"  "VAULT()(address)" --rpc-url "$RPC_URL"

# Deployed bytecode present?
cast code "$HOOK" --rpc-url "$RPC_URL" | wc -c    # should be > 0
```

## 3) Drive the demo (emits on-chain events)

Use the **third** printed hex from the deploy logs as the demo `poolId` (we mine a salt; the demo just uses it as an identifier for telemetry).

```bash
export DEMO_HOOK="$HOOK"
export DEMO_POOL_ID=0x0000000000000000000000000000000000000000000000000000000000001b8e  # <= paste your printed hex

forge script script/EmitDemo.s.sol:EmitDemo \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation \
  -vv
```

## 4) Inspect the transaction

Copy the tx hash printed by Foundry (e.g., `0x3376f4...`) and:

```bash
TX=<paste tx hash>
cast receipt "$TX" --rpc-url "$RPC_URL"
cast tx      "$TX" --rpc-url "$RPC_URL"
```

You should see:

* A `Vault` log with topic for `ModeApplied(poolId, mode=1, epoch=2, reason="demo", ...)`.
* A `Hook` log for `AdminApplyModeForDemo(poolId, ...)`.

## 5) (Optional) Read hook config

```bash
# tuple (widenBps, riskOffBps, minFlipInterval)
cast call "$HOOK" "cfg()(uint16,uint16,uint32)" --rpc-url "$RPC_URL"
```

> Updating config requires the **admin** account. If `cast send ... setLVRConfig(...)` reverts, verify you’re signing with the same key that did the deploy (that key is the admin in our deploy script).

---

## Troubleshooting quick map

* **`block is out of range`**
  Add `--skip-simulation` to `forge script` (we already do above).

* **403 / network not enabled** from Alchemy
  Enable **Unichain Sepolia** for your Alchemy app; confirm `echo "$RPC_URL"` prints the expected URL.

* **`nonce too low`**
  Wait for pending tx to confirm (`cast nonce "$ADDR"`), then re-run.

* **`VAULT:NOT_HOOK` / `VAULT:NOT_ADMIN`**
  Only use artifacts from the **DeployLocal.s.sol** run (it wires the hook during deploy). If you manually set envs to old addresses, you can get these.

---

That’s the up-to-date, known-good E2E. This is exactly what you just did successfully with:

* `VAULT=0x9D1993Dc39603bd88631637520c61fD571997cA0`
* `HOOK=0xD656892746b6ea05Ce19Ec7d18093B7eE9AD00C0`
* `DEMO_POOL_ID=0x...1b8e`

If you want, I can generate a tiny `SetConfig.s.sol` helper that reads the admin on-chain and sets `widenBps/riskOffBps/minFlipInterval` using your deployer key.
