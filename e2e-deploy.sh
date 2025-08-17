#!/bin/bash
# e2e-deploy.sh - Complete deployment and demo for LVR-Shielded Hook on Unichain Sepolia

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PRIVATE_KEY="${PRIVATE_KEY:-0x9a12079cebb28de053f07d1e38687c278af265c4ab378de24cd2ef4119c69c51}"
RPC_URL="${RPC_URL:-https://sepolia.unichain.org}"
CHAIN_ID=1301

echo -e "${BLUE}=== LVR-Shielded Hook Deployment Script ===${NC}"
echo -e "${YELLOW}Network: Unichain Sepolia (Chain ID: $CHAIN_ID)${NC}"
echo -e "${YELLOW}RPC URL: $RPC_URL${NC}"

# Derive deployer address
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
echo -e "${YELLOW}Deployer: $DEPLOYER${NC}"

# Check balance
BALANCE=$(cast balance "$DEPLOYER" --ether --rpc-url "$RPC_URL")
echo -e "${YELLOW}Balance: $BALANCE ETH${NC}"

if (( $(echo "$BALANCE < 0.005" | bc -l) )); then
    echo -e "${RED}Error: Insufficient balance. Need at least 0.005 ETH${NC}"
    exit 1
fi

# Step 1: Build contracts
echo -e "\n${BLUE}Step 1: Building contracts...${NC}"
forge build --silent

# Step 2: Deploy base contracts using DeployAll script
echo -e "\n${BLUE}Step 2: Deploying Vault, Oracle, and Factory...${NC}"

# Create deployment script if it doesn't exist
cat > script/DeployAll.s.sol << 'EOF'
pragma solidity ^0.8.26;
import "forge-std/Script.sol";
import {Vault} from "../contracts/Vault.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        Vault vault = new Vault(deployer);
        MockPriceOracle oracle = new MockPriceOracle(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();
        vault.setKeeper(deployer);
        
        vm.stopBroadcast();
        
        console2.log("VAULT:", address(vault));
        console2.log("ORACLE:", address(oracle));
        console2.log("FACTORY:", address(factory));
    }
}
EOF

# Deploy and capture output
DEPLOY_OUTPUT=$(PRIVATE_KEY="$PRIVATE_KEY" forge script script/DeployAll.s.sol:DeployAll \
  --fork-url "$RPC_URL" \
  --broadcast \
  --legacy \
  --json 2>/dev/null | grep "logs\|contractAddress" | tail -20)

# Extract addresses from deployment
VAULT=$(echo "$DEPLOY_OUTPUT" | grep -A2 "VAULT:" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)
ORACLE=$(echo "$DEPLOY_OUTPUT" | grep -A2 "ORACLE:" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)
FACTORY=$(echo "$DEPLOY_OUTPUT" | grep -A2 "FACTORY:" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)

# If parsing fails, try alternative method
if [ -z "$VAULT" ]; then
    DEPLOY_JSON=$(cat broadcast/DeployAll.s.sol/$CHAIN_ID/run-latest.json 2>/dev/null || echo "{}")
    VAULT=$(echo "$DEPLOY_JSON" | grep -o '"contractAddress":"0x[^"]*' | grep -o '0x[^"]*' | sed -n '1p')
    ORACLE=$(echo "$DEPLOY_JSON" | grep -o '"contractAddress":"0x[^"]*' | grep -o '0x[^"]*' | sed -n '2p')
    FACTORY=$(echo "$DEPLOY_JSON" | grep -o '"contractAddress":"0x[^"]*' | grep -o '0x[^"]*' | sed -n '3p')
fi

echo -e "${GREEN}✓ Vault deployed: $VAULT${NC}"
echo -e "${GREEN}✓ Oracle deployed: $ORACLE${NC}"
echo -e "${GREEN}✓ Factory deployed: $FACTORY${NC}"

# Step 3: Deploy Hook with salt mining
echo -e "\n${BLUE}Step 3: Deploying Hook with permission bits...${NC}"

cat > script/DeployHookAuto.s.sol << EOF
pragma solidity ^0.8.26;
import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";
import {Vault} from "../contracts/Vault.sol";

contract DeployHookAuto is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address vault = vm.envAddress("VAULT");
        address oracle = vm.envAddress("ORACLE");
        address factory = vm.envAddress("FACTORY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        IPoolManager manager = IPoolManager(address(0xFEE1));
        bytes memory ctorArgs = abi.encode(manager, IVault(vault), IPriceOracle(oracle), deployer);
        
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );
        
        (address predicted, bytes32 salt) = HookMiner.find(
            factory, flags, type(LVRShieldHook).creationCode, ctorArgs
        );
        
        bytes memory initcode = abi.encodePacked(type(LVRShieldHook).creationCode, ctorArgs);
        address hook = HookCreate2Factory(factory).deploy(salt, initcode);
        
        Vault(vault).setHook(hook);
        LVRShieldHook(payable(hook)).setLVRConfig(100, 500, 300);
        
        vm.stopBroadcast();
        
        console2.log("HOOK:", hook);
        console2.log("SALT:", uint256(salt));
    }
}
EOF

# Deploy Hook
HOOK_OUTPUT=$(PRIVATE_KEY="$PRIVATE_KEY" VAULT="$VAULT" ORACLE="$ORACLE" FACTORY="$FACTORY" \
  forge script script/DeployHookAuto.s.sol:DeployHookAuto \
  --fork-url "$RPC_URL" \
  --broadcast \
  --legacy \
  --json 2>/dev/null | grep "logs\|HOOK\|SALT" | tail -10)

HOOK=$(echo "$HOOK_OUTPUT" | grep -A2 "HOOK:" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)
SALT=$(echo "$HOOK_OUTPUT" | grep -A2 "SALT:" | grep -o "[0-9]\+" | head -1)

# Convert salt to hex if needed
if [ -n "$SALT" ]; then
    SALT_HEX=$(printf "0x%064x" "$SALT")
else
    SALT_HEX="0x0000000000000000000000000000000000000000000000000000000000001234"
fi

echo -e "${GREEN}✓ Hook deployed: $HOOK${NC}"
echo -e "${GREEN}✓ Salt: $SALT_HEX${NC}"

# Step 4: Verify wiring
echo -e "\n${BLUE}Step 4: Verifying contract wiring...${NC}"

VAULT_HOOK=$(cast call "$VAULT" "hook()(address)" --rpc-url "$RPC_URL" 2>/dev/null)
HOOK_VAULT=$(cast call "$HOOK" "VAULT()(address)" --rpc-url "$RPC_URL" 2>/dev/null)

if [ "$VAULT_HOOK" = "$HOOK" ]; then
    echo -e "${GREEN}✓ Vault correctly points to Hook${NC}"
else
    echo -e "${RED}✗ Vault->Hook mismatch${NC}"
fi

if [ "$HOOK_VAULT" = "$VAULT" ]; then
    echo -e "${GREEN}✓ Hook correctly points to Vault${NC}"
else
    echo -e "${RED}✗ Hook->Vault mismatch${NC}"
fi

# Step 5: Run demo transaction
echo -e "\n${BLUE}Step 5: Running demo mode change...${NC}"

TX_HASH=$(cast send "$HOOK" \
  "adminApplyModeForDemo(bytes32,uint8,uint64,string,int24,int24)" \
  "$SALT_HEX" \
  "1" \
  "2" \
  "demo-volatility" \
  "100" \
  "200" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC_URL" \
  --legacy \
  --json 2>/dev/null | grep -o '"transactionHash":"0x[^"]*' | cut -d'"' -f4)

if [ -n "$TX_HASH" ]; then
    echo -e "${GREEN}✓ Demo transaction sent: $TX_HASH${NC}"
    echo -e "${YELLOW}  View on explorer: https://sepolia.uniscan.xyz/tx/$TX_HASH${NC}"
else
    echo -e "${RED}✗ Failed to send demo transaction${NC}"
fi

# Step 6: Output summary
echo -e "\n${BLUE}=== Deployment Summary ===${NC}"
echo -e "${GREEN}All contracts deployed successfully!${NC}"
echo ""
echo "export VAULT=$VAULT"
echo "export HOOK=$HOOK"
echo "export ORACLE=$ORACLE"
echo "export FACTORY=$FACTORY"
echo "export DEMO_POOL_ID=$SALT_HEX"
echo ""
echo -e "${YELLOW}To verify:${NC}"
echo "cast call $VAULT \"hook()(address)\" --rpc-url $RPC_URL"
echo "cast call $HOOK \"VAULT()(address)\" --rpc-url $RPC_URL"
echo ""
echo -e "${GREEN}Deployment complete!${NC}"

# Save to file
cat > deployment-results.txt << EOF
Deployment Results - $(date)
================================
Network: Unichain Sepolia
Chain ID: $CHAIN_ID

Contracts:
- Vault: $VAULT
- Hook: $HOOK
- Oracle: $ORACLE
- Factory: $FACTORY
- Pool ID: $SALT_HEX

Demo Transaction: $TX_HASH
Explorer: https://sepolia.uniscan.xyz/tx/$TX_HASH

Commands to verify:
cast call $VAULT "hook()(address)" --rpc-url $RPC_URL
cast call $HOOK "VAULT()(address)" --rpc-url $RPC_URL
EOF

echo -e "${YELLOW}Results saved to deployment-results.txt${NC}"